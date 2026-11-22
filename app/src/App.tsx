import { useAuth } from './lib/auth'
import { useLang } from './lib/i18n'
import { configured } from './lib/supabase'
import Header from './screens/Header'
import AuthScreen from './screens/AuthScreen'
import Home from './screens/Home'

export default function App() {
  const { session, loading } = useAuth()
  const { t } = useLang()

  return (
    <div className="shell">
      <Header />
      {!configured ? (
        <div className="card">
          <h2>{t.cfgTitle}</h2>
          <p className="lbl">{t.cfgBody}</p>
        </div>
      ) : loading ? (
        <div className="center">{t.loading}</div>
      ) : session ? (
        <Home />
      ) : (
        <AuthScreen />
      )}
    </div>
  )
}
