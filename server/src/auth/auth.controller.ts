import {
  Controller,
  Post,
  Body,
  HttpCode,
  HttpStatus,
  Get,
  UseGuards,
} from '@nestjs/common';
import { AuthService } from './auth.service';
import { ValidateInviteDto } from './dto/validate-invite.dto';
import { RegisterInviteDto } from './dto/register-invite.dto';
import { LoginDto, RefreshTokenDto } from './dto/login.dto';
import { JwtAuthGuard } from './guards/jwt-auth.guard';
import { CurrentUser } from './decorators/current-user.decorator';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('invitation/validate')
  @HttpCode(HttpStatus.OK)
  async validateInvitation(@Body() dto: ValidateInviteDto) {
    return await this.authService.validateInvitation(dto.code);
  }

  @Post('register-with-invite')
  @HttpCode(HttpStatus.CREATED)
  async registerWithInvite(@Body() dto: RegisterInviteDto) {
    return await this.authService.registerWithInvite(dto);
  }

  @Post('login')
  @HttpCode(HttpStatus.OK)
  async login(@Body() dto: LoginDto) {
    return await this.authService.login(dto);
  }

  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  async refresh(@Body() dto: RefreshTokenDto) {
    return await this.authService.refresh(dto.refresh_token);
  }

  @Get('me')
  @UseGuards(JwtAuthGuard)
  async getProfile(@CurrentUser() user: any) {
    return user;
  }
}
