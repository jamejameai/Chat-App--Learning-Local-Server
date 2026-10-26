import { IsNotEmpty, IsString } from 'class-validator';

export class AddFriendDto {
  @IsString()
  @IsNotEmpty()
  identifier: string; // Accepts username, phone number, or user UUID
}
