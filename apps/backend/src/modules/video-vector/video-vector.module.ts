import { Global, Module } from '@nestjs/common';
import { VideoVectorService } from './video-vector.service';

@Global()
@Module({
  providers: [VideoVectorService],
  exports: [VideoVectorService],
})
export class VideoVectorModule {}
