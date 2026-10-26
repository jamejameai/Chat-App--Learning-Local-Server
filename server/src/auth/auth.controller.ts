import {
  Controller,
  Post,
  Body,
  HttpCode,
  HttpStatus,
  Get,
  Patch,
  Query,
  UseGuards,
} from '@nestjs/common';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { AuthService } from './auth.service';
import { ValidateInviteDto } from './dto/validate-invite.dto';
import { RegisterInviteDto } from './dto/register-invite.dto';
import { RegisterDto, UpdateProfileDto } from './dto/register.dto';
import { LoginDto, RefreshTokenDto } from './dto/login.dto';
import { JwtAuthGuard } from './guards/jwt-auth.guard';
import { CurrentUser } from './decorators/current-user.decorator';

// Credential-guessing surface: 10 attempts / minute / client IP
const AUTH_ATTEMPT_LIMIT = { default: { limit: 10, ttl: 60_000 } };

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('invitation/validate')
  @UseGuards(ThrottlerGuard)
  @Throttle(AUTH_ATTEMPT_LIMIT)
  @HttpCode(HttpStatus.OK)
  async validateInvitation(@Body() dto: ValidateInviteDto) {
    return await this.authService.validateInvitation(dto.code);
  }

  @Post('register-with-invite')
  @UseGuards(ThrottlerGuard)
  @Throttle(AUTH_ATTEMPT_LIMIT)
  @HttpCode(HttpStatus.CREATED)
  async registerWithInvite(@Body() dto: RegisterInviteDto) {
    return await this.authService.registerWithInvite(dto);
  }

  @Post('register')
  @UseGuards(ThrottlerGuard)
  @Throttle(AUTH_ATTEMPT_LIMIT)
  @HttpCode(HttpStatus.CREATED)
  async register(@Body() dto: RegisterDto) {
    return await this.authService.register(dto);
  }

  @Post('login')
  @UseGuards(ThrottlerGuard)
  @Throttle(AUTH_ATTEMPT_LIMIT)
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
  async getProfile(@CurrentUser('userId') userId: string) {
    return await this.authService.getUserProfile(userId);
  }

  @Patch('profile')
  @UseGuards(JwtAuthGuard)
  async updateProfile(
    @CurrentUser('userId') userId: string,
    @Body() dto: UpdateProfileDto,
  ) {
    return await this.authService.updateProfile(userId, dto);
  }

  @Get('users')
  @UseGuards(JwtAuthGuard)
  async listUsers(
    @CurrentUser('userId') userId: string,
    @Query('search') search?: string,
  ) {
    return await this.authService.listUsers(userId, search);
  }
}
