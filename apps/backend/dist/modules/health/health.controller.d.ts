import { ConfigService } from '@nestjs/config';
export declare class HealthController {
    private readonly configService;
    constructor(configService: ConfigService);
    getRoot(): {
        status: string;
        service: string;
        instanceId: string;
        timestamp: string;
    };
    getHealth(): {
        status: string;
        instanceId: string;
        uptime: number;
        timestamp: string;
    };
}
