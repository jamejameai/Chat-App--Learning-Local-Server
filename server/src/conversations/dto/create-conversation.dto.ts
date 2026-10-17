import {
  IsArray,
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  MinLength,
} from 'class-validator';

export class CreateConversationDto {
  @IsString()
  @IsIn(['direct', 'group', 'channel'])
  type: 'direct' | 'group' | 'channel';

  @IsString()
  @IsOptional()
  @MinLength(1)
  title?: string;

  @IsArray()
  @IsString({ each: true })
  @IsNotEmpty()
  participant_user_ids: string[];
}
