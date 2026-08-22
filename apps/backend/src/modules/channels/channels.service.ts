import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class ChannelsService {
  constructor(private readonly prisma: PrismaService) {}

  async findAll() {
    return this.prisma.channel.findMany({
      where: { isActive: true },
      orderBy: { name: 'asc' },
    });
  }

  async createRequest(data: { channelUrl: string; notes?: string; submittedBy?: string }) {
    return this.prisma.channelRequest.create({
      data: {
        channelUrl: data.channelUrl,
        notes: data.notes,
        submittedBy: data.submittedBy,
      },
    });
  }
}
