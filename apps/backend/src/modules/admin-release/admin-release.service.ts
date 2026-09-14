import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';

export interface PendingCommit {
  sha: string;
  message: string;
  author: string;
}

export interface PromotionStatus {
  canPromote: boolean;
  isBuilding: boolean;
  aheadCount: number;
  commits: PendingCommit[];
  latestProductionTag: string;
  activeRunUrl?: string;
  message?: string;
}

@Injectable()
export class AdminReleaseService {
  private readonly logger = new Logger(AdminReleaseService.name);

  constructor(private readonly configService: ConfigService) {}

  private getHeaders(): Record<string, string> {
    const token =
      this.configService.get<string>('githubToken') ||
      process.env.GITHUB_TOKEN ||
      process.env.GITHUB_FEEDBACK_TOKEN;

    if (!token) {
      throw new BadRequestException('GITHUB_TOKEN is not configured on the server');
    }

    return {
      Authorization: `Bearer ${token}`,
      Accept: 'application/vnd.github+json',
      'User-Agent': 'ChristianTube-AdminRelease/1.0',
    };
  }

  private getRepo(): string {
    return (
      this.configService.get<string>('githubRepo') ||
      process.env.GITHUB_REPO ||
      'rozariopersonal/Christian-Tube'
    );
  }

  async getPromotionStatus(): Promise<PromotionStatus> {
    const repo = this.getRepo();
    const headers = this.getHeaders();

    try {
      // 1. Check if a production release workflow is currently running on main
      let isBuilding = false;
      let activeRunUrl: string | undefined;

      try {
        const runsRes = await axios.get(
          `https://api.github.com/repos/${repo}/actions/workflows/release.yml/runs`,
          {
            headers,
            params: {
              branch: 'main',
              status: 'in_progress',
              per_page: 1,
            },
          },
        );

        if (runsRes.data?.workflow_runs?.length > 0) {
          isBuilding = true;
          activeRunUrl = runsRes.data.workflow_runs[0].html_url;
        }
      } catch (e: any) {
        this.logger.warn(`Failed to check workflow runs: ${e.message}`);
      }

      // 2. Compare main and develop
      let aheadCount = 0;
      let commits: PendingCommit[] = [];

      try {
        const compareRes = await axios.get(
          `https://api.github.com/repos/${repo}/compare/main...develop`,
          { headers },
        );

        if (compareRes.data) {
          aheadCount = compareRes.data.ahead_by || 0;
          commits = (compareRes.data.commits || []).slice(0, 15).map((c: any) => ({
            sha: (c.sha || '').substring(0, 7),
            message: (c.commit?.message || '').split('\n')[0],
            author: c.commit?.author?.name || c.author?.login || 'Unknown',
          }));
        }
      } catch (e: any) {
        this.logger.warn(`Failed to compare branches: ${e.message}`);
      }

      // 3. Fetch latest production release tag
      let latestProductionTag = 'Unknown';
      try {
        const relRes = await axios.get(
          `https://api.github.com/repos/rozariopersonal/Christian-Tube-Releases/releases/latest`,
          { headers },
        );
        latestProductionTag = relRes.data?.tag_name || 'Unknown';
      } catch (e: any) {
        this.logger.warn(`Failed to fetch latest release: ${e.message}`);
      }

      const canPromote = !isBuilding && aheadCount > 0;
      let message = '';
      if (isBuilding) {
        message = 'A production release is currently building and deploying.';
      } else if (aheadCount === 0) {
        message = 'Production is already up to date with develop.';
      } else {
        message = `${aheadCount} commit(s) in Beta ready to promote to Production.`;
      }

      return {
        canPromote,
        isBuilding,
        aheadCount,
        commits,
        latestProductionTag,
        activeRunUrl,
        message,
      };
    } catch (e: any) {
      this.logger.error(`Error calculating promotion status: ${e.message}`, e.stack);
      throw new BadRequestException(e.message || 'Failed to determine promotion status');
    }
  }

  async promoteToProduction(adminEmail: string): Promise<{ success: boolean; message: string }> {
    const repo = this.getRepo();
    const headers = this.getHeaders();

    this.logger.log(`Admin ${adminEmail} requested production release promotion.`);

    // Pre-flight validation
    const status = await this.getPromotionStatus();
    if (status.isBuilding) {
      throw new BadRequestException('A production release is already currently in progress.');
    }
    if (status.aheadCount === 0) {
      throw new BadRequestException(
        'Production is already up to date with develop. No changes to release.',
      );
    }

    try {
      const commitMessage = `chore(release): promote develop to production [Admin: ${adminEmail}]`;
      const mergeRes = await axios.post(
        `https://api.github.com/repos/${repo}/merges`,
        {
          base: 'main',
          head: 'develop',
          commit_message: commitMessage,
        },
        { headers },
      );

      this.logger.log(`Successfully merged develop into main: ${mergeRes.data?.sha || 'merged'}`);

      return {
        success: true,
        message: 'Production release successfully triggered! The build pipeline is now running.',
      };
    } catch (e: any) {
      this.logger.error(`Failed to merge develop into main: ${e.message}`, e.response?.data);
      const detail = e.response?.data?.message || e.message;
      throw new BadRequestException(`Failed to trigger production release: ${detail}`);
    }
  }
}
