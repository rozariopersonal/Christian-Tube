import { Controller, Get, Query } from "@nestjs/common";
import { VideosService } from "./videos.service";

@Controller("api/search")
export class SearchController {
  constructor(private readonly videosService: VideosService) {}

  @Get()
  search(
    @Query("q") q?: string,
    @Query("type") type?: "VIDEO" | "SHORT" | "ALL",
    @Query("category") category?: string,
    @Query("limit") limit?: number,
    @Query("offset") offset?: number,
  ) {
    return this.videosService.findAll({
      search: q,
      type,
      category,
      limit,
      offset,
    });
  }
}
