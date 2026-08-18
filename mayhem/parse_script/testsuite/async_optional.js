async function fetchAll(urls) {
  const results = [];
  for (const url of urls) {
    try {
      const res = await fetch(url);
      results.push(res?.ok ? await res.json() : null);
    } catch (e) {
      results.push(e?.message ?? "unknown error");
    }
  }
  return results;
}

const config = {
  base: "https://example.com",
  headers: { "x-api-key": "abc" },
};

const url = config?.base ?? "http://localhost";
fetchAll([url]).then((r) => console.log(r.length));

(async function () {
  let x = null;
  x ??= { nested: { value: 42 } };
  console.log(x?.nested?.value ?? -1);
})();
