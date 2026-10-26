import { IsIn, IsNotEmpty, IsOptional, IsString, MaxLength } from 'class-validator';

export class UpdateUserStatusDto {
  @IsString()
  @IsNotEmpty()
  @IsIn(['active', 'suspended', 'deactivated'])
  status: 'active' | 'suspended' | 'deactivated';
}

export class UpdateUserRoleDto {
  @IsString()
  @IsNotEmpty()
  @IsIn(['member', 'superadmin', 'owner'])
  role: 'member' | 'superadmin' | 'owner';
}

export class BroadcastMessageDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  title: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(500)
  message: string;
}
