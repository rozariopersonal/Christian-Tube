import { CanActivate, ExecutionContext } from '@nestjs/common';
import { AuthGuard } from './auth.guard';
export declare class AdminGuard extends AuthGuard implements CanActivate {
    canActivate(context: ExecutionContext): Promise<boolean>;
}
