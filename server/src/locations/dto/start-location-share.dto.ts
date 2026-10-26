import {
  ArrayNotEmpty,
  ArrayUnique,
  IsHexadecimal,
  IsArray,
  IsString,
  Length,
  IsUUID,
} from "class-validator";
import { UpdateLocationDto } from "./update-location.dto";

export class StartLocationShareDto extends UpdateLocationDto {
  @IsArray()
  @ArrayNotEmpty()
  @ArrayUnique()
  @IsUUID("4", { each: true })
  viewer_ids: string[];

  @IsString()
  @Length(64, 64)
  @IsHexadecimal()
  stop_token: string;
}
