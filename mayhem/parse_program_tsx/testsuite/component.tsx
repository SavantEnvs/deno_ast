import { useState } from "react";

interface Props<T> {
  items: T[];
  render: (item: T) => JSX.Element;
}

export function List<T>({ items, render }: Props<T>) {
  const [selected, setSelected] = useState<number | null>(null);

  return (
    <ul className="list">
      {items.map((item, i) => (
        <li
          key={i}
          className={i === selected ? "selected" : undefined}
          onClick={() => setSelected(i)}
        >
          {render(item)}
        </li>
      ))}
    </ul>
  );
}

export const App = () => (
  <>
    <h1>Title</h1>
    <List items={[1, 2, 3]} render={(n) => <span>{n}</span>} />
  </>
);
