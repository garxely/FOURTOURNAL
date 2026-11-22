import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../lib/auth'
import { useLang } from '../lib/i18n'

// Pantalla provisional: solo comprueba que RLS deja ver TUS datos y que el alta creó perfil y categorías.
export default function Home() {
  const { session } = useAuth()
  const { t } = useLang()
  const [name, setName] = useState<string | null>(null)
  const [cats, setCats] = useState<number | null>(null)
  const [err, setErr] = useState('')

  useEffect(() => {
    let alive = true
    ;(async () => {
      const p = await supabase.from('profiles').select('display_name').eq('id', session!.user.id).maybeSingle()
      const c = await supabase.from('transaction_categories').select('id', { count: 'exact', head: true })
      if (!alive) return
      if (p.error || c.error) setErr((p.error || c.error)!.message)
      setName(p.data ? p.data.display_name : null)
      setCats(c.count ?? 0)
    })()
    return () => { alive = false }
  }, [session])

  return (
    <>
      <div className="card hero">
        <div className="lbl">{t.welcome}</div>
        <h2 className="serif" style={{ fontSize: 30, margin: '2px 0 0' }}>{name ?? '…'}</h2>
        <div className="lbl">{session!.user.email}</div>
      </div>

      <div className="card">
        <h2 style={{ marginTop: 0 }}>{t.connTitle}</h2>
        <div className="row"><span>{t.profile}</span>
          <span className={name !== null ? 'p' : 'n'}>{name !== null ? t.ok : t.missing}</span></div>
        <div className="row"><span>{t.categories}</span>
          <span className={cats === 15 ? 'p' : 'n'}>{cats === null ? '…' : `${cats} / 15`}</span></div>
        {err && <div className="err">{err}</div>}
        <p className="lbl">{t.connNote}</p>
      </div>

      <button className="btn" onClick={() => supabase.auth.signOut()}>{t.signout}</button>
    </>
  )
}
