import { useLang } from '../lib/i18n'

export default function Header() {
  const { lang, setLang, t } = useLang()
  return (
    <div className="top">
      <div>
        <h1 className="brand">FORTOURNAL</h1>
        <div className="tag">{t.tagline}</div>
      </div>
      <div className="ctl">
        <button className={'pill' + (lang === 'es' ? ' on' : '')} onClick={() => setLang('es')}>ES</button>
        <button className={'pill' + (lang === 'en' ? ' on' : '')} onClick={() => setLang('en')}>EN</button>
      </div>
    </div>
  )
}
