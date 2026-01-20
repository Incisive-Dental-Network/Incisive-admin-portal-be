import { INestApplication } from '@nestjs/common';
import { PrismaClient, Prisma } from '@prisma/client';
import * as bcrypt from 'bcrypt';

// Admin credentials from environment
const ADMIN_EMAIL = process.env.ADMIN_EMAIL || 'admin@example.com';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'admin123';
const SESSION_SECRET = process.env.SESSION_SECRET || 'super-secret-session-key';

// Models with composite primary keys that AdminJS cannot handle
const EXCLUDED_MODELS = [
  'orders_current',      // Composite key: caseid + productid
  'orders_stage',        // @@ignore - no valid unique identifier
  'product_lab_markup',  // Composite key: lab_id + lab_product_id
  'product_lab_rev_share', // Composite key: lab_id + lab_product_id + fee_schedule_name
];

// Get all model names from Prisma DMMF, excluding problematic models
function getAllModelNames(): string[] {
  return Prisma.dmmf.datamodel.models
    .map((model) => model.name)
    .filter((name) => !EXCLUDED_MODELS.includes(name));
}

export async function setupAdminJS(app: INestApplication, prisma: PrismaClient) {
  // Dynamic imports for ESM modules
  const { default: AdminJS } = await import('adminjs');
  const AdminJSExpress = await import('@adminjs/express');
  const { Database, Resource, getModelByName } = await import('@adminjs/prisma');

  // Register Prisma adapter
  AdminJS.registerAdapter({ Database, Resource });

  // Get all models from Prisma schema
  const modelNames = getAllModelNames();
  console.log('Discovered Prisma models:', modelNames);

  // Auto-generate resources for all models
  const resources = modelNames.map((modelName) => {
    const baseResource = {
      resource: { model: getModelByName(modelName), client: prisma },
      options: {
        navigation: { name: modelName },
      } as any,
    };

    // Custom options for specific models
    if (modelName === 'users') {
      baseResource.options = {
        navigation: { name: 'User Management', icon: 'User' },
        properties: {
          password: { isVisible: false },
          refresh_token: { isVisible: false },
        },
        actions: {
          new: {
            before: async (request: any) => {
              if (request.payload?.password) {
                request.payload.password = await bcrypt.hash(request.payload.password, 10);
              }
              return request;
            },
          },
          edit: {
            before: async (request: any) => {
              if (request.payload?.password) {
                request.payload.password = await bcrypt.hash(request.payload.password, 10);
              }
              return request;
            },
          },
        },
      };
    }

    if (modelName === 'audit_logs') {
      baseResource.options = {
        navigation: { name: 'Audit Logs', icon: 'Activity' },
        actions: {
          new: { isAccessible: false },
          edit: { isAccessible: false },
          delete: { isAccessible: false },
        },
      };
    }

    return baseResource;
  });

  // Create AdminJS instance
  const adminJs = new AdminJS({
    rootPath: '/admin',
    loginPath: '/admin/login',
    logoutPath: '/admin/logout',
    branding: {
      companyName: 'Incisive Admin',
      logo: false,
      withMadeWithLove: false,
    },
    resources,
  });

  // Authentication function
  const authenticate = async (email: string, password: string) => {
    // Check hardcoded admin
    if (email === ADMIN_EMAIL && password === ADMIN_PASSWORD) {
      return { email: ADMIN_EMAIL, title: 'Super Admin' };
    }

    // Check database admin users
    const user = await prisma.users.findUnique({ where: { email } });
    if (user && user.role === 'ADMIN' && user.is_active) {
      const isValid = await bcrypt.compare(password, user.password);
      if (isValid) {
        return { email: user.email, title: `${user.first_name} ${user.last_name}` };
      }
    }

    return null;
  };

  // Build authenticated router
  const adminRouter = AdminJSExpress.buildAuthenticatedRouter(
    adminJs,
    {
      authenticate,
      cookieName: 'adminjs',
      cookiePassword: SESSION_SECRET,
    },
    null,
    {
      resave: false,
      saveUninitialized: false,
      secret: SESSION_SECRET,
    },
  );

  // Get Express instance and mount AdminJS
  const expressApp = app.getHttpAdapter().getInstance();
  expressApp.use(adminJs.options.rootPath, adminRouter);

  return adminJs;
}
