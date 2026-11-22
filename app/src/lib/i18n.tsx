import { createContext, useContext, useState, type ReactNode } from 'react'

export type Lang = 'es' | 'en'
const es = {
  tagline: 'Finanzas personales y familiares',
  signin: 'Iniciar sesión', signup: 'Crear cuenta', signout: 'Cerrar sesión',
  email: 'Correo', password: 'Contraseña', name: 'Tu nombre',
  pwHint: 'Mínimo 8 caracteres', working: 'Un momento…',
  checkMail: 'Cuenta creada. Revisa tu correo para confirmarla y luego inicia sesión.',
  welcome: 'Bienvenida', connTitle: 'Conexión con tu base de datos',
  profile: 'Perfil', categories: 'Categorías iniciales', ok: 'listo', missing: 'falta',
  connNote: 'Esta pantalla solo comprueba que el registro creó tu perfil y tus categorías. Las demás pantallas vienen en las siguientes etapas.',
  cfgTitle: 'Falta configurar Supabase',
  cfgBody: 'Agrega VITE_SUPABASE_URL y VITE_SUPABASE_ANON_KEY en las variables de entorno y vuelve a desplegar.',
  loading: 'Cargando…',
}
export type Dict = typeof es
const en: Dict = {
  tagline: 'Personal and family finances',
  signin: 'Sign in', signup: 'Create account', signout: 'Sign out',
  email: 'Email', password: 'Password', name: 'Your name',
  pwHint: 'At least 8 characters', working: 'One moment…',
  checkMail: 'Account created. Check your email to confirm it, then sign in.',
  welcome: 'Welcome', connTitle: 'Database connection',
  profile: 'Profile', categories: 'Starter categories', ok: 'ready', missing: 'missing',
  connNote: 'This screen only checks that signing up created your profile and categories. The other screens come in the next stages.',
  cfgTitle: 'Supabase is not configured',
  cfgBody: 'Add VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY as environment variables and redeploy.',
  loading: 'Loading…',
}
const T: Record<Lang, Dict> = { es, en }
type Ctx = { lang: Lang; t: Dict; setLang: (l: Lang) => void }
const LangCtx = createContext<Ctx>({ lang: 'es', t: es, setLang: () => {} })

export function LangProvider({ children }: { children: ReactNode }) {
  const [lang, setL] = useState<Lang>(() => {
    try { return localStorage.getItem('ft-lang') === 'en' ? 'en' : 'es' } catch { return 'es' }
  })
  const setLang = (l: Lang) => { setL(l); try { localStorage.setItem('ft-lang', l) } catch { /* ignorar */ } }
  return <LangCtx.Provider value={{ lang, t: T[lang], setLang }}>{children}</LangCtx.Provider>
}
export const useLang = () => useContext(LangCtx)
