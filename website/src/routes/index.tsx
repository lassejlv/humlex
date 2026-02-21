import { createFileRoute, Link } from "@tanstack/react-router";
import { fetchReleases } from "@/lib/releases.server";
import { Button } from "@/components/ui/button";
import { Apple, Download, Github } from "lucide-react";

export const Route = createFileRoute("/")({
  loader: async () => {
    const releases = await fetchReleases();
    return { releases };
  },
  component: HomePage,
});

function HomePage() {
  const { releases } = Route.useLoaderData();
  const latest = releases[0];
  const downloadUrl = latest?.universal?.url 
    ?? latest?.appleSilicon?.url 
    ?? latest?.intel?.url;

  return (
    <div className="min-h-screen bg-background text-foreground">
      <nav className="flex items-center justify-between px-6 py-4 max-w-5xl mx-auto">
        <Link to="/" className="flex items-center gap-2 font-semibold">
          <img src="/icon.png" alt="" className="w-6 h-6 rounded" />
          Humlex
        </Link>
        <a href="https://github.com/lassejlv/humlex" className="text-muted-foreground hover:text-foreground">
          <Github className="w-5 h-5" />
        </a>
      </nav>

      <main className="px-6 py-20 max-w-5xl mx-auto">
        <div className="grid lg:grid-cols-[1fr_1.3fr] gap-12 items-center">
          <div className="text-left">
            <h1 className="text-4xl font-semibold tracking-tight mb-4">
              One app. Every model. Pure native.
            </h1>
            <p className="text-muted-foreground mb-8">
              Native client for OpenAI, Anthropic, and local models.
              Keep your API keys in Keychain.
            </p>

            {downloadUrl ? (
              <Button size="lg" className="gap-2" asChild>
                <a href={downloadUrl}>
                  <Apple className="w-4 h-4" />
                  Download {latest?.version}
                </a>
              </Button>
            ) : (
              <Button size="lg" disabled>
                <Download className="w-4 h-4" />
                No release available
              </Button>
            )}

            <p className="mt-4 text-xs text-muted-foreground">
              macOS 14+ required · Free & open source
            </p>

            {releases.length > 1 && (
              <div className="mt-12 border-t pt-8">
                <p className="text-sm text-muted-foreground mb-4">Previous versions</p>
                <div className="space-y-2">
                  {releases.slice(1, 4).map((r) => {
                    const url = r.universal?.url ?? r.appleSilicon?.url ?? r.intel?.url;
                    return url ? (
                      <a
                        key={r.version}
                        href={url}
                        className="flex justify-between text-sm py-2 px-3 rounded hover:bg-muted"
                      >
                        <span>{r.version}</span>
                        <span className="text-muted-foreground">{r.publishedAt}</span>
                      </a>
                    ) : null;
                  })}
                </div>
              </div>
            )}
          </div>

          <img
            src="/example1.png"
            alt="Humlex preview"
            className="w-full"
          />
        </div>
      </main>
    </div>
  );
}
