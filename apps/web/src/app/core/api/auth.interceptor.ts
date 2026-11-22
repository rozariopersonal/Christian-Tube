import { HttpInterceptorFn } from '@angular/common/http';
import { AppConfig } from '../config/app-config';

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  if (!req.url.startsWith(AppConfig.apiBaseUrl) || req.headers.has('Authorization')) {
    return next(req);
  }

  let token: string | null = null;
  try {
    token = localStorage.getItem('auth_token');
  } catch {
    token = null;
  }

  if (!token) {
    return next(req);
  }

  return next(
    req.clone({
      setHeaders: {
        Authorization: `Bearer ${token}`,
      },
    }),
  );
};
