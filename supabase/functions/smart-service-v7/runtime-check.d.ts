declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (request: Request) => Promise<Response>): void;
};
declare module 'https://esm.sh/@supabase/supabase-js@2.95.0' {
  export const createClient: (...args: any[]) => any;
}
