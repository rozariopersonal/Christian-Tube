import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class UsersService {
  private readonly logger = new Logger(UsersService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
  ) {}

  isAdmin(email?: string): boolean {
    if (!email) return false;
    const adminEmails = this.configService.get<string[]>('adminEmails') || [];
    return adminEmails.includes(email.trim().toLowerCase());
  }

  async syncUser(data: {
    id: string;
    email: string;
    displayName?: string;
    photoUrl?: string;
  }) {
    const role = this.isAdmin(data.email) ? 'ADMIN' : 'USER';

    const user = await this.prisma.user.upsert({
      where: { email: data.email },
      update: {
        displayName: data.displayName || undefined,
        photoUrl: data.photoUrl || undefined,
        role,
        lastLoginAt: new Date(),
      },
      create: {
        id: data.id,
        email: data.email,
        displayName: data.displayName || 'User',
        photoUrl: data.photoUrl || null,
        role,
        isBlocked: false,
        lastLoginAt: new Date(),
      },
    });

    return user;
  }

  async findAll(query?: { search?: string }) {
    const where: any = {};
    if (query?.search) {
      where.OR = [
        { email: { contains: query.search, mode: 'insensitive' } },
        { displayName: { contains: query.search, mode: 'insensitive' } },
      ];
    }

    return this.prisma.user.findMany({
      where,
      orderBy: { lastLoginAt: 'desc' },
    });
  }

  async findOne(id: string) {
    const user = await this.prisma.user.findUnique({
      where: { id },
    });
    if (!user) {
      throw new NotFoundException(`User with ID ${id} not found`);
    }
    return user;
  }

  async toggleBlock(id: string) {
    const user = await this.findOne(id);
    return this.prisma.user.update({
      where: { id },
      data: { isBlocked: !user.isBlocked },
    });
  }

  async blockUser(id: string) {
    return this.prisma.user.update({
      where: { id },
      data: { isBlocked: true },
    });
  }

  async unblockUser(id: string) {
    return this.prisma.user.update({
      where: { id },
      data: { isBlocked: false },
    });
  }
}
