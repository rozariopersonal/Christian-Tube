"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const core_1 = require("@nestjs/core");
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const express_1 = require("express");
const helmet_1 = __importDefault(require("helmet"));
const express_rate_limit_1 = __importDefault(require("express-rate-limit"));
const app_module_1 = require("./app.module");
async function bootstrap() {
    const logger = new common_1.Logger('PrivateTubeBootstrap');
    const app = await core_1.NestFactory.create(app_module_1.AppModule);
    const configService = app.get(config_1.ConfigService);
    const appName = configService.get('appName') || 'PrivateTube';
    const port = configService.get('port') || 3000;
    app.use((0, express_1.text)({ type: ['application/xml', 'text/xml', 'application/atom+xml'] }));
    app.use((0, helmet_1.default)());
    app.enableCors({
        origin: true,
        credentials: true,
    });
    app.use((0, express_rate_limit_1.default)({
        windowMs: 60 * 1000,
        max: 100,
    }));
    app.useGlobalPipes(new common_1.ValidationPipe({
        whitelist: true,
        transform: true,
    }));
    await app.listen(port, '0.0.0.0');
    logger.log(`🚀 ${appName} Backend Engine running on http://0.0.0.0:${port}`);
}
bootstrap();
//# sourceMappingURL=main.js.map