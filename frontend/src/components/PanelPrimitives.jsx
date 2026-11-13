export function PanelSection({ title, subtitle, action, children }) {
    return (<section className="panel-section">
      <div className="section-heading">
        <div>
          <h3>{title}</h3>
          {subtitle && <p>{subtitle}</p>}
        </div>
        {action}
      </div>
      {children}
    </section>);
}
export function StatusDot({ state }) {
    return <span className={`status-dot status-dot-${state}`} aria-hidden="true"/>;
}
export function StatusPill({ label, state }) {
    return <span className={`status-pill status-pill-${state}`}><StatusDot state={state}/>{label}</span>;
}
export function CodeTag({ children }) {
    return <span className="code-tag">{children}</span>;
}
