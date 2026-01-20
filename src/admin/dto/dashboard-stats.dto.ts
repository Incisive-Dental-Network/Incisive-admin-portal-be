import { ApiProperty } from '@nestjs/swagger';

export class UserStatsDto {
  @ApiProperty({ description: 'Total number of users' })
  total: number;

  @ApiProperty({ description: 'Number of active users' })
  active: number;

  @ApiProperty({ description: 'Number of inactive users' })
  inactive: number;

  @ApiProperty({ description: 'Number of admin users' })
  admins: number;

  @ApiProperty({ description: 'Number of regular users' })
  users: number;

  @ApiProperty({ description: 'Number of viewer users' })
  viewers: number;
}

export class RecentActivityDto {
  @ApiProperty({ description: 'Total logins today' })
  loginsToday: number;

  @ApiProperty({ description: 'New users this week' })
  newUsersThisWeek: number;

  @ApiProperty({ description: 'New users this month' })
  newUsersThisMonth: number;
}

export class AuditSummaryDto {
  @ApiProperty({ description: 'Total audit log entries' })
  totalLogs: number;

  @ApiProperty({ description: 'Logs in the last 24 hours' })
  logsLast24Hours: number;

  @ApiProperty({ description: 'Action breakdown' })
  actionBreakdown: Record<string, number>;
}

export class DashboardStatsDto {
  @ApiProperty({ type: UserStatsDto })
  users: UserStatsDto;

  @ApiProperty({ type: RecentActivityDto })
  recentActivity: RecentActivityDto;

  @ApiProperty({ type: AuditSummaryDto })
  auditSummary: AuditSummaryDto;

  @ApiProperty({ description: 'Timestamp of the stats' })
  generatedAt: Date;
}
