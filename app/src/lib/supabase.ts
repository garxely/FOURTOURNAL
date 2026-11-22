import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const anon = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

// Solo la clave pública (anon). La seguridad real la dan las políticas RLS de la base.
export const configured = Boolean(url && anon)
export const supabase = createClient(url || 'https://placeholder.supabase.co', anon || 'placeholder')
