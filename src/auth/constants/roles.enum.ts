export enum Role {
  ADMIN = 'ADMIN',
  USER = 'USER',
  VIEWER = 'VIEWER',
}

// Role hierarchy - higher index = more permissions
export const ROLE_HIERARCHY: Role[] = [Role.VIEWER, Role.USER, Role.ADMIN];

// Check if a role has at least the required permission level
export function hasMinimumRole(userRole: Role, requiredRole: Role): boolean {
  const userIndex = ROLE_HIERARCHY.indexOf(userRole);
  const requiredIndex = ROLE_HIERARCHY.indexOf(requiredRole);
  return userIndex >= requiredIndex;
}
