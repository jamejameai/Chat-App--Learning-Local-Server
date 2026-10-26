import { IsHexadecimal, IsString, Length } from "class-validator";

export class RevokeLocationShareDto {
  @IsString()
  @Length(64, 64)
  @IsHexadecimal()
  stop_token: string;
}
