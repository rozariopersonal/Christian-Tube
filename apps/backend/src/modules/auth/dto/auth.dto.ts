import { IsNotEmpty, IsOptional, IsString, MaxLength } from 'class-validator';

export class GoogleAuthDto {
  @IsString()
  @IsNotEmpty()
  idToken!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(128)
  deviceId!: string;

  @IsOptional()
  @IsString()
  @MaxLength(128)
  deviceLabel?: string;
}

export class GuestAuthDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(128)
  deviceId!: string;

  @IsOptional()
  @IsString()
  @MaxLength(128)
  deviceLabel?: string;

  @IsOptional()
  @IsString()
  @MaxLength(128)
  displayName?: string;
}

export class RefreshAuthDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(128)
  sessionId!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(512)
  refreshToken!: string;
}
