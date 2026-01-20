import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcrypt';

const prisma = new PrismaClient();

async function main() {
  console.log('Seeding database...');

  // Create admin user
  const hashedPassword = await bcrypt.hash('admin123', 10);

  const admin = await prisma.users.upsert({
    where: { email: 'admin@example.com' },
    update: {},
    create: {
      email: 'admin@example.com',
      password: hashedPassword,
      first_name: 'Admin',
      last_name: 'User',
      role: 'ADMIN',
      is_active: true,
    },
  });

  console.log('Created admin user:', admin.email);

  // Create a regular user
  const userPassword = await bcrypt.hash('user123', 10);

  const user = await prisma.users.upsert({
    where: { email: 'user@example.com' },
    update: {},
    create: {
      email: 'user@example.com',
      password: userPassword,
      first_name: 'Regular',
      last_name: 'User',
      role: 'USER',
      is_active: true,
    },
  });

  console.log('Created regular user:', user.email);

  // Create a viewer user
  const viewerPassword = await bcrypt.hash('viewer123', 10);

  const viewer = await prisma.users.upsert({
    where: { email: 'viewer@example.com' },
    update: {},
    create: {
      email: 'viewer@example.com',
      password: viewerPassword,
      first_name: 'Viewer',
      last_name: 'User',
      role: 'VIEWER',
      is_active: true,
    },
  });

  console.log('Created viewer user:', viewer.email);

  console.log('Seeding completed!');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
