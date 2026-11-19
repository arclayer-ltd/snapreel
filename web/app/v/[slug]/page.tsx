import { Suspense } from "react";

// Placeholder. The watch-page session builds the public player here (see docs/pro/API.md).
// Next 16 with cacheComponents: route params are runtime data, so read them inside <Suspense>.
async function Slug({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  return <>Video {slug}</>;
}

export default function WatchPage({ params }: PageProps<"/v/[slug]">) {
  return (
    <main className="p-8">
      <Suspense fallback={null}>
        <Slug params={params} />
      </Suspense>
    </main>
  );
}
