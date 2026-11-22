import {
  HttpContextToken,
  HttpErrorResponse,
  HttpInterceptorFn,
} from '@angular/common/http';
import { inject } from '@angular/core';
import { catchError, from, switchMap, throwError } from 'rxjs';
import { AppConfig } from '../config/app-config';
import { AuthTokenStore } from '../auth/auth-token.store';
import { AuthService } from '../auth/auth.service';

export const AUTH_RETRIED = new HttpContextToken<boolean>(() => false);

function isAuthEndpoint(url: string): boolean {
  return (
    url.includes('/auth/google') ||
    url.includes('/auth/guest') ||
    url.includes('/auth/refresh') ||
    url.includes('/auth/logout')
  );
}

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  if (!req.url.startsWith(AppConfig.apiBaseUrl)) {
    return next(req);
  }

  const tokenStore = inject(AuthTokenStore);
  const authService = inject(AuthService);

  const token = tokenStore.getAccessToken();
  const authedReq = token
    ? req.clone({ setHeaders: { Authorization: `Bearer ${token}` } })
    : req;

  return next(authedReq).pipe(
    catchError((err: unknown) => {
      if (
        err instanceof HttpErrorResponse &&
        err.status === 401 &&
        !req.context.get(AUTH_RETRIED) &&
        !isAuthEndpoint(req.url)
      ) {
        return from(authService.refreshSession()).pipe(
          switchMap((newToken) => {
            if (!newToken) {
              return throwError(() => err);
            }
            const retriedReq = req.clone({
              setHeaders: { Authorization: `Bearer ${newToken}` },
              context: req.context.set(AUTH_RETRIED, true),
            });
            return next(retriedReq);
          }),
        );
      }
      return throwError(() => err);
    }),
  );
};
