import { IsNotEmpty, IsOptional, IsString, IsUUID, Matches, MaxLength } from 'class-validator';

export class CreateStoryDto {
  @IsUUID()
  attachment_id: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(256)
  media_key: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(128)
  media_iv: string;

  @IsString()
  @Matches(/^[0-9a-fA-F]{64}$/)
  media_sha256: string;

  @IsString()
  @Matches(/^image\/(jpeg|png|heic|webp)$/)
  mime_type: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  caption?: string;
}
