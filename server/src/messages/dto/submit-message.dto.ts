import {
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  IsUUID,
} from 'class-validator';

export class SubmitMessageDto {
  @IsUUID()
  @IsNotEmpty()
  id: string; // Client-assigned UUID for guaranteed idempotency

  @IsString()
  @IsIn([
    'e2ee_text',
    'e2ee_attachment',
    'e2ee_voice',
    'e2ee_call_signal',
    'system',
  ])
  @IsNotEmpty()
  envelope_type:
    | 'e2ee_text'
    | 'e2ee_attachment'
    | 'e2ee_voice'
    | 'e2ee_call_signal'
    | 'system';

  @IsString()
  @IsNotEmpty()
  encrypted_payload: string; // Base64 ciphertext

  @IsString()
  @IsNotEmpty()
  iv: string; // Base64 IV

  @IsUUID()
  @IsOptional()
  reply_to_message_id?: string;
}
