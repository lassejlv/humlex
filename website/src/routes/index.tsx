import { createFileRoute, Link } from "@tanstack/react-router";
import { fetchReleases, type Release } from "@/lib/releases.server";
import { Button } from "@/components/ui/button";
import { Download, Apple, Cpu } from "lucide-react";
import { useState } from "react";

export const Route = createFileRoute("/")({
  loader: async () => {
    const releases = await fetchReleases();
    return { releases };
  },
  component: HomePage,
});

function HomePage() {
  const { releases } = Route.useLoaderData();
  const latestRelease = releases[0];

  return (
    <div className="min-h-screen bg-background">
      <Navbar />
      <Hero latestRelease={latestRelease} />
      <DemoSection />
      <DownloadSection releases={releases} />
    </div>
  );
}

function Navbar() {
  return (
    <nav className="fixed top-0 left-0 right-0 z-50 bg-background/80 backdrop-blur-md border-b border-border">
      <div className="max-w-5xl mx-auto px-6 h-16 flex items-center justify-between">
        <Link to="/" className="flex items-center gap-2">
          <img src="/icon.png" alt="Humlex" className="w-6 h-6 rounded-lg" />
          <span className="text-lg font-medium tracking-tight">Humlex</span>
        </Link>

        <div className="hidden md:flex items-center gap-8">
          <a
            href="#features"
            className="text-sm text-muted-foreground hover:text-foreground transition-colors"
          >
            Features
          </a>
          <a
            href="#download"
            className="text-sm text-muted-foreground hover:text-foreground transition-colors"
          >
            Download
          </a>
        </div>

        <Button asChild size="sm" className="rounded-full px-4">
          <a href="#download">Download</a>
        </Button>
      </div>
    </nav>
  );
}

function Hero({ latestRelease }: { latestRelease?: Release }) {
  return (
    <section className="pt-32 pb-16 px-6">
      <div className="max-w-3xl mx-auto text-center">
        <h1 className="text-4xl md:text-6xl font-semibold tracking-tight mb-5">
          AI Chat for macOS
        </h1>
        <p className="text-lg text-muted-foreground mb-8 max-w-xl mx-auto leading-relaxed">
          Native macOS app for chatting with multiple AI providers. Fast,
          secure, and built for the Mac.
        </p>

        <div className="flex flex-col sm:flex-row items-center justify-center gap-3">
          <Button size="lg" className="gap-2 rounded-full px-6" asChild>
            <a href="#download">
              <Apple className="w-4 h-4" />
              Download
            </a>
          </Button>
          <Button
            variant="ghost"
            size="lg"
            className="rounded-full px-6"
            asChild
          >
            <a href="#features">Learn more</a>
          </Button>
        </div>

        {latestRelease && (
          <p className="mt-6 text-sm text-muted-foreground">
            {latestRelease.version} · macOS 14+ (Intel & Apple Silicon)
          </p>
        )}
      </div>
    </section>
  );
}

function DemoSection() {
  return (
    <section id="features" className="py-16 px-6">
      <div className="max-w-4xl mx-auto">
        <div className="rounded-2xl overflow-hidden bg-card border border-border shadow-sm">
          <video
            autoPlay
            muted
            loop
            playsInline
            className="w-full aspect-video object-cover"
            poster="/example1.png"
          >
            <source src="/example1.mp4" type="video/mp4" />
          </video>
        </div>

        <div className="mt-16 grid md:grid-cols-2 gap-8">
          <Feature
            title="Multiple Providers"
            description="Chat with OpenAI, Anthropic, OpenRouter, Vercel AI, Gemini, and more."
          />
          <Feature
            title="Agent Mode"
            description="Enable AI agents to edit files, run commands, and execute MCP tools directly from chat."
          />
          <Feature
            title="Native macOS"
            description="Built for macOS with dark mode, keyboard shortcuts, and native UI patterns."
          />
          <Feature
            title="Secure"
            description="API keys stored in macOS Keychain. Your credentials never touch disk."
          />
        </div>
      </div>
    </section>
  );
}

function Feature({
  title,
  description,
}: {
  title: string;
  description: string;
}) {
  return (
    <div>
      <h3 className="text-base font-medium mb-2">{title}</h3>
      <p className="text-sm text-muted-foreground leading-relaxed">
        {description}
      </p>
    </div>
  );
}

function DownloadSection({ releases }: { releases: Release[] }) {
  const latestRelease = releases[0];
  const [arch, setArch] = useState<"auto" | "intel" | "apple">("auto");

  const getDownloadInfo = () => {
    if (!latestRelease) return null;

    if (arch === "auto" && latestRelease.universal) {
      return {
        url: latestRelease.universal.url,
        size: latestRelease.universal.size,
        label: "Universal",
      };
    }

    if ((arch === "auto" || arch === "apple") && latestRelease.appleSilicon) {
      return {
        url: latestRelease.appleSilicon.url,
        size: latestRelease.appleSilicon.size,
        label: "Apple Silicon",
      };
    }

    if ((arch === "auto" || arch === "intel") && latestRelease.intel) {
      return {
        url: latestRelease.intel.url,
        size: latestRelease.intel.size,
        label: "Intel",
      };
    }

    if (latestRelease.universal) {
      return {
        url: latestRelease.universal.url,
        size: latestRelease.universal.size,
        label: "Universal",
      };
    }

    return null;
  };

  const downloadInfo = getDownloadInfo();
  const hasMultipleArchs =
    latestRelease &&
    ((latestRelease.intel && latestRelease.appleSilicon) ||
      (latestRelease.universal &&
        (latestRelease.intel || latestRelease.appleSilicon)));

  return (
    <section id="download" className="py-24 px-6 bg-muted/50">
      <div className="max-w-xl mx-auto text-center">
        <h2 className="text-2xl font-semibold mb-3">Download Humlex</h2>
        <p className="text-muted-foreground mb-8">
          Free and open source. Choose your Mac type below.
        </p>

        {latestRelease ? (
          <div className="p-6 rounded-xl bg-card border border-border">
            <p className="text-sm text-muted-foreground mb-1">Latest Release</p>
            <p className="text-xl font-semibold mb-1">
              {latestRelease.version}
            </p>
            <p className="text-sm text-muted-foreground mb-6">
              {latestRelease.publishedAt}
            </p>

            {hasMultipleArchs && (
              <div className="flex items-center justify-center gap-1 p-1 bg-muted rounded-full mb-6 w-fit mx-auto">
                <button
                  onClick={() => setArch("auto")}
                  className={`px-4 py-1.5 text-sm font-medium rounded-full transition-all ${
                    arch === "auto"
                      ? "bg-background text-foreground shadow-sm"
                      : "text-muted-foreground hover:text-foreground"
                  }`}
                >
                  Auto
                </button>
                <button
                  onClick={() => setArch("intel")}
                  className={`px-4 py-1.5 text-sm font-medium rounded-full transition-all flex items-center gap-1.5 ${
                    arch === "intel"
                      ? "bg-background text-foreground shadow-sm"
                      : "text-muted-foreground hover:text-foreground"
                  }`}
                >
                  Intel
                </button>
                <button
                  onClick={() => setArch("apple")}
                  className={`px-4 py-1.5 text-sm font-medium rounded-full transition-all flex items-center gap-1.5 ${
                    arch === "apple"
                      ? "bg-background text-foreground shadow-sm"
                      : "text-muted-foreground hover:text-foreground"
                  }`}
                >
                  Apple Silicon
                </button>
              </div>
            )}

            {downloadInfo ? (
              <>
                <Button className="gap-2 rounded-full px-6" asChild>
                  <a href={downloadInfo.url}>
                    <Download className="w-4 h-4" />
                    Download DMG
                  </a>
                </Button>
                <p className="mt-3 text-xs text-muted-foreground">
                  {downloadInfo.label} · {downloadInfo.size}
                </p>
              </>
            ) : (
              <Button className="gap-2 rounded-full px-6" disabled>
                <Download className="w-4 h-4" />
                No DMG Available
              </Button>
            )}

            <p className="mt-4 text-xs text-muted-foreground">
              macOS 14+ required
            </p>
          </div>
        ) : (
          <div className="p-6 rounded-xl bg-card border border-border">
            <p className="text-muted-foreground">No releases available.</p>
          </div>
        )}

        {releases.length > 1 && (
          <div className="mt-8">
            <p className="text-sm text-muted-foreground mb-4">
              Previous releases
            </p>
            <div className="space-y-2">
              {releases.slice(1, 4).map((release) => {
                const asset =
                  release.universal || release.appleSilicon || release.intel;
                return asset ? (
                  <a
                    key={release.version}
                    href={asset.url}
                    className="flex items-center justify-between p-3 rounded-lg bg-card border border-border hover:bg-accent transition-colors"
                  >
                    <span className="text-sm font-medium">
                      {release.version}
                    </span>
                    <span className="text-sm text-muted-foreground">
                      {release.publishedAt}
                    </span>
                  </a>
                ) : null;
              })}
            </div>
          </div>
        )}
      </div>
    </section>
  );
}
