import { Controller, Get, Post, Req, UseGuards } from '@nestjs/common';
import { AdminGuard } from '../../guards/admin.guard';
import { AdminReleaseService, PromotionStatus } from './admin-release.service';

@Controller(['admin/releases', 'api/admin/releases'])
@UseGuards(AdminGuard)
export class AdminReleaseController {
  constructor(private readonly adminReleaseService: AdminReleaseService) {}

  @Get('status')
  async getStatus(): Promise<PromotionStatus> {
    return this.adminReleaseService.getPromotionStatus();
  }

  @Post('promote')
  async promote(@Req() req: any): Promise<{ success: boolean; message: string }> {
    const adminEmail = req.user?.email || 'admin@christiantube.org';
    return this.adminReleaseService.promoteToProduction(adminEmail);
  }
}
