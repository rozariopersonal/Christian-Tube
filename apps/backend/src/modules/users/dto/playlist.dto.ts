import {
  Allow,
  IsArray,
  IsInt,
  IsOptional,
  IsString,
  Min,
} from 'class-validator';

export class CreatePlaylistDto {
  @IsOptional()
  @IsString()
  id?: string;

  @IsString()
  title!: string;

  @IsOptional()
  @IsString()
  description?: string | null;

  @IsOptional()
  @Allow()
  clientUpdatedAt?: number | string;
}

export class UpdatePlaylistDto {
  @IsOptional()
  @IsString()
  title?: string;

  @IsOptional()
  @IsString()
  description?: string | null;

  @IsOptional()
  @Allow()
  clientUpdatedAt?: number | string;
}

export class DeletePlaylistDto {
  @IsOptional()
  @Allow()
  clientUpdatedAt?: number | string;
}

export class AddPlaylistItemDto {
  @IsString()
  videoId!: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  position?: number;

  @IsOptional()
  @Allow()
  clientUpdatedAt?: number | string;
}

export class ReorderPlaylistItemsDto {
  @IsArray()
  @IsString({ each: true })
  videoIds!: string[];

  @IsOptional()
  @Allow()
  clientUpdatedAt?: number | string;
}
