// Exercises the JSX-vs-generic angle-bracket ambiguity swc's lexer/parser must disambiguate in
// .tsx mode: `<T,>` (trailing comma) forces "this is a generic type parameter", not a JSX tag.
const identity = <T,>(x: T): T => x;

type Maybe<T> = T | null | undefined;

function Badge({ value }: { value: Maybe<number> }) {
  return value == null ? null : <span className="badge">{value}</span>;
}

export default function Page({ ok }: { ok: boolean }) {
  return (
    <div>
      {ok
        ? <Badge value={identity(1)} />
        : <>
            <Badge value={null} />
            <em>no value</em>
          </>}
      {/* comment inside jsx */}
      <input disabled={!ok} value={ok ? "yes" : "no"} data-x={`n=${identity(2)}`} />
    </div>
  );
}
