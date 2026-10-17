import { IsIn, IsNumber, IsOptional, Max, Min } from 'class-validator';

export class CreateInvitationDto {
  @IsOptional()
  @IsIn(['member', 'superadmin'])
  role?: 'member' | 'superadmin' = 'member';

  @IsOptional()
  @IsNumber()
  @Min(1)
  @Max(90)
  expires_in_days?: number = 14;
}
