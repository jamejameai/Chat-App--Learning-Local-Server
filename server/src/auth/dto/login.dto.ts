import { IsNotEmpty, IsOptional, IsString } from 'class-validator';

export class LoginDto {
  @IsString()
  @IsNotEmpty()
  username: string; // Accepts username OR phone number

  @IsString()
  @IsNotEmpty()
  password: string;

  @IsString()
  @IsOptional()
  device_id?: string;

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
}

export class RefreshTokenDto {
  @IsString()
  @IsNotEmpty()
  refresh_token: string;
}
