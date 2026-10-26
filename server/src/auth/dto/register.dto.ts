import {
  IsArray,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  IsBoolean,
  IsIn,
  MaxLength,
  ArrayMaxSize,
  MinLength,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { OneTimePrekeyDto } from './register-invite.dto';

export class DeveloperProjectDto {
  @IsString()
  @IsNotEmpty()
  id: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  title: string;

  @IsString()
  @IsOptional()
  @MaxLength(500)
  summary?: string;

  @IsArray()
  @ArrayMaxSize(20)
  @IsString({ each: true })
  @IsOptional()
  technologies?: string[];

  @IsString()
  @IsOptional()
  @MaxLength(500)
  repository_url?: string;

  @IsString()
  @IsOptional()
  @MaxLength(500)
  live_url?: string;

  @IsBoolean()
  @IsOptional()
  is_pinned?: boolean;
}

export class DeveloperSocialLinksDto {
  @IsString()
  @IsOptional()
  @MaxLength(500)
  linkedin_url?: string;

  @IsString()
  @IsOptional()
  @MaxLength(500)
  instagram_url?: string;

  @IsString()
  @IsOptional()
  @MaxLength(500)
  x_url?: string;
}

export class DeveloperProfileDto {
  @IsString()
  @IsOptional()
  @MaxLength(160)
  headline?: string;

  @IsArray()
  @ArrayMaxSize(40)
  @IsString({ each: true })
  @IsOptional()
  skills?: string[];

  @IsArray()
  @ArrayMaxSize(20)
  @ValidateNested({ each: true })
  @Type(() => DeveloperProjectDto)
  @IsOptional()
  projects?: DeveloperProjectDto[];

  @IsString()
  @IsOptional()
  @MaxLength(500)
  website_url?: string;

  @IsString()
  @IsOptional()
  @MaxLength(500)
  github_url?: string;

  @ValidateNested()
  @Type(() => DeveloperSocialLinksDto)
  @IsOptional()
  social_links?: DeveloperSocialLinksDto;

  @IsString()
  @IsOptional()
  @MaxLength(200)
  currently_building?: string;

  @IsString()
  @IsOptional()
  @MaxLength(40)
  @IsIn(['open_to_opportunities', 'available_for_work', 'not_available'])
  work_availability?: string;

  @IsString()
  @IsOptional()
  @MaxLength(100)
  location?: string;
}

export class RegisterDto {
  @IsString()
  @IsNotEmpty()
  @MinLength(3)
  username: string;

  @IsString()
  @IsNotEmpty()
  display_name: string;

  @IsString()
  @IsNotEmpty()
  @MinLength(6)
  password: string;

  @IsString()
  @IsOptional()
  phone_number?: string;

  @IsString()
  @IsOptional()
  avatar_url?: string;

  @IsString()
  @IsOptional()
  device_name?: string;

  @IsString()
  @IsOptional()
  identity_key_pub?: string;

  @IsString()
  @IsOptional()
  signed_prekey_pub?: string;

  @IsString()
  @IsOptional()
  signed_prekey_sig?: string;

  @IsNumber()
  @IsOptional()
  signed_prekey_id?: number;

  @IsArray()
  @IsOptional()
  @ValidateNested({ each: true })
  @Type(() => OneTimePrekeyDto)
  one_time_prekeys?: OneTimePrekeyDto[];
}

export class UpdateProfileDto {
  @IsString()
  @IsOptional()
  display_name?: string;

  @IsString()
  @IsOptional()
  username?: string;

  @IsString()
  @IsOptional()
  phone_number?: string;

  @IsString()
  @IsOptional()
  avatar_url?: string;

  @IsString()
  @IsOptional()
  bio?: string;

  @IsString()
  @IsOptional()
  cover_url?: string;

  @IsString()
  @IsOptional()
  border_template?: string;

  @IsString()
  @IsOptional()
  name_color?: string;

  @ValidateNested()
  @Type(() => DeveloperProfileDto)
  @IsOptional()
  developer_profile?: DeveloperProfileDto;
}

