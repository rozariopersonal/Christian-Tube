import { Module } from "@nestjs/common";
import { EmbeddingService } from "./embedding.service";
import { EmbeddingStatusController } from "./embedding-status.controller";

@Module({
  controllers: [EmbeddingStatusController],
  providers: [EmbeddingService],
  exports: [EmbeddingService],
})
export class EmbeddingModule {}
