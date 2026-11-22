import { useState, type FormEvent } from 'react'
import { supabase } from '../lib/supabase'
import { useLang } from '../lib/i18n'

export default function AuthScreen() {
  const { t } = useLang()
  const [mode, setMode] = useState<'in' | 'up'>('in')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [name, setName] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [info, setInfo] = useState('')

  async function submit(e: FormEvent) {
    e.preventDefault()
    setError(''); setInfo(''); setBusy(true)
    try {
      if (mode === 'in') {
        const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password })
        if (error) setError(error.message)
      } else {
        // handle_new_user() en la base lee display_name y crea perfil, preferencias y 15 categorías.
        const { data, error } = await supabase.auth.signUp({
          email: email.trim(),
          password,
          options: { data: { display_name: name.trim() } },
        })
        if (error) setError(error.message)
        else if (!data.session) setInfo(t.checkMail)
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <form className="card hero" onSubmit={submit}>
      <div className="tabs">
        <button type="button" className={'pill' + (mode === 'in' ? ' on' : '')} onClick={() => setMode('in')}>{t.signin}</button>
        <button type="button" className={'pill' + (mode === 'up' ? ' on' : '')} onClick={() => setMode('up')}>{t.signup}</button>
      </div>

      {mode === 'up' && (
        <label>{t.name}
          <input value={name} onChange={e => setName(e.target.value)} required maxLength={40} autoComplete="nickname" />
        </label>
      )}
      <label>{t.email}
        <input type="email" value={email} onChange={e => setEmail(e.target.value)} required autoComplete="email" />
      </label>
      <label>{t.password}
        <input type="password" value={password} onChange={e => setPassword(e.target.value)} required minLength={8}
               autoComplete={mode === 'in' ? 'current-password' : 'new-password'} />
      </label>
      {mode === 'up' && <div className="lbl">{t.pwHint}</div>}

      <div className="err" role="alert">{error}</div>
      {info && <div className="msg">{info}</div>}
      <button className="btn fill" disabled={busy} style={{ marginTop: 12 }}>
        {busy ? t.working : mode === 'in' ? t.signin : t.signup}
      </button>
    </form>
  )
}
