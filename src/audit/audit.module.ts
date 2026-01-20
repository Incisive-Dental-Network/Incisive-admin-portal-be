import { Global, Module } from '@nestjs/common';
import { AuditService } from './audit.service';

@Global() // Available everywhere without importing
@Module({
  providers: [AuditService],
  exports: [AuditService],
})
export class AuditModule {}
