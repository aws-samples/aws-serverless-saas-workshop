export interface User {
  user_name: string;
  tenant_id?: string;
  email: string;
  created?: string;
  modified?: string;
  enabled?: boolean;
  status?: string;
  verified?: boolean;
}
