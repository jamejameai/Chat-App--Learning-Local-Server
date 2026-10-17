import {
  IsArray,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  MinLength,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';

export class OneTimePrekeyDto {
  @IsNumber()
  key_id: number;

  @IsString()
  @IsNotEmpty()
  public_key: string;
}

export class RegisterInviteDto {
  @IsString()
  @IsNotEmpty()
  invitation_code: string;

  @IsString()
  @IsNotEmpty()
  @MinLength(3)
  username: string;

  @IsString()
  @IsNotEmpty()
  display_name: string;

  @IsString()
  @IsNotEmpty()
  @MinLength(8)
  password: string;

  @IsString()
  @IsNotEmpty()
  device_name: string;

  @IsString()
  @IsNotEmpty()
  identity_key_pub: string; // Base64 Curve25519 identity key

  @IsString()
  @IsNotEmpty()
  signed_prekey_pub: string; // Base64 Curve25519 signed prekey

  @IsString()
  @IsNotEmpty()
  signed_prekey_sig: string; // Base64 Ed25519 signature

  @IsNumber()
  signed_prekey_id: number;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => OneTimePrekeyDto)
  @IsOptional()
  one_time_prekeys?: OneTimePrekeyDto[];
}
