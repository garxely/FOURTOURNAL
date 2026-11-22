# FORTOURNAL

Carpetas del repositorio:

- `supabase/` — base de datos (YA instalada en tu Supabase; no hace falta volver a ejecutar nada):
  `1_supabase_instalar.sql`, `2_supabase_verificar.sql`, `3_supabase_comparar_esquema.sql` (solo lectura).
- `prototype/` — el prototipo actual (referencia visual y funcional). Es lo que está publicado en fortournal.vercel.app.
- `app/` — la aplicación real (React + Vite + TypeScript + Supabase). Etapa 2: registro, inicio de sesión
  y una pantalla provisional que comprueba tu perfil y tus 15 categorías.

## Cómo probar la app real SIN tocar el prototipo publicado

1. En GitHub, sube estas tres carpetas a tu repositorio (Add file → Upload files).
2. En Vercel crea un proyecto NUEVO (Add New → Project) con ese repositorio y estos ajustes:
   - Root Directory: `app`
   - Framework Preset: Vite
3. Antes de desplegar, en Environment Variables agrega:
   - `VITE_SUPABASE_URL` = la URL de tu proyecto (Supabase → Project Settings → API → Project URL)
   - `VITE_SUPABASE_ANON_KEY` = la clave pública `anon` (Project Settings → API → anon public)
   NUNCA uses la clave `service_role`: es secreta y no debe estar en la app.
4. Despliega. Tu prototipo en fortournal.vercel.app sigue igual.

Para correrla en una computadora: `cd app`, copia `.env.example` a `.env.local`, llénalo, luego `npm install` y `npm run dev`.
