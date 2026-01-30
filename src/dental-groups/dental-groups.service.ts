import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class DentalGroupsService {
  constructor(private prisma: PrismaService) {}

  /**
   * Get all dental group IDs and names from the dental_groups table
   * Optionally filter by search term (searches name and ID)
   */
  async getDentalGroupIds(search?: string): Promise<{ dentalGroups: { dental_group_id: number; name: string }[] }> {
    const where: any = { is_active: true };

    if (search && search.trim()) {
      const searchTerm = search.trim();
      const searchNum = parseInt(searchTerm, 10);

      where.OR = [
        { name: { contains: searchTerm, mode: 'insensitive' } },
      ];

      // If search term is a valid number, also search by ID
      if (!isNaN(searchNum)) {
        where.OR.push({ dental_group_id: BigInt(searchNum) });
      }
    }

    const dentalGroups = await this.prisma.dental_groups.findMany({
      where,
      select: { dental_group_id: true, name: true },
      orderBy: { name: 'asc' },
    });

    return {
      dentalGroups: dentalGroups.map((group) => ({
        dental_group_id: Number(group.dental_group_id),
        name: group.name,
      })),
    };
  }
}
