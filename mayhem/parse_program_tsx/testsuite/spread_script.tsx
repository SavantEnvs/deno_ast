// No import/export at all — exercises parse_program's auto-detected SCRIPT path (rather than
// module) while still in .tsx (JSX-enabled) media type.
function Row(props: { id: number; children?: unknown }) {
  const rest = { ...props, extra: true };
  return <tr {...rest} key={props.id} />;
}

const rows = [1, 2, 3].map((id) => <Row id={id}>{id}</Row>);
console.log(rows.length);
