"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var FeedbackService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.FeedbackService = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
let FeedbackService = FeedbackService_1 = class FeedbackService {
    constructor(configService) {
        this.configService = configService;
        this.logger = new common_1.Logger(FeedbackService_1.name);
    }
    async submitFeedback(dto) {
        const token = process.env.GITHUB_FEEDBACK_TOKEN ||
            process.env.GITHUB_TOKEN ||
            this.configService.get('githubFeedbackToken');
        const repo = process.env.GITHUB_REPO ||
            this.configService.get('githubRepo') ||
            'rozariopersonal/Christian-Tube';
        if (!token) {
            this.logger.warn('GITHUB_FEEDBACK_TOKEN is not configured. Feedback recorded in server logs:');
            this.logger.log(`[Feedback - ${dto.screenContext || 'General'}] ${dto.title}`);
            this.logger.log(dto.body);
            return {
                success: true,
                message: 'Feedback received and recorded (token not set).',
            };
        }
        try {
            const response = await fetch(`https://api.github.com/repos/${repo}/issues`, {
                method: 'POST',
                headers: {
                    Authorization: `Bearer ${token}`,
                    Accept: 'application/vnd.github+json',
                    'Content-Type': 'application/json',
                    'User-Agent': 'ChristianApp-Backend',
                },
                body: JSON.stringify({
                    title: dto.title,
                    body: dto.body,
                    labels: ['user-feedback'],
                }),
            });
            if (!response.ok) {
                const errText = await response.text();
                this.logger.error(`GitHub API error (${response.status}): ${errText}`);
                return {
                    success: false,
                    message: `GitHub API error: ${response.status}`,
                };
            }
            const issueData = await response.json();
            this.logger.log(`Created GitHub Issue #${issueData.number}: ${issueData.html_url}`);
            return {
                success: true,
                issueNumber: issueData.number,
                issueUrl: issueData.html_url,
            };
        }
        catch (err) {
            this.logger.error(`Failed to post issue to GitHub: ${err.message}`, err.stack);
            return {
                success: false,
                message: err.message || 'Failed to communicate with GitHub',
            };
        }
    }
};
exports.FeedbackService = FeedbackService;
exports.FeedbackService = FeedbackService = FeedbackService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [config_1.ConfigService])
], FeedbackService);
//# sourceMappingURL=feedback.service.js.map