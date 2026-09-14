import { Controller, Get } from "@nestjs/common";
import { EmbeddingService } from "./embedding.service";

@Controller(["embedding", "api/embedding"])
export class EmbeddingStatusController {
  constructor(private readonly embeddingService: EmbeddingService) {}

  @Get("status")
  getStatus() {
    return this.embeddingService.getStatus();
  }
}