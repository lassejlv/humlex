import { createFileRoute, Link } from "@tanstack/react-router";
import { fetchReleases, type Release } from "@/lib/releases.server";
import { Button } from "@/components/ui/button";
import {
  Download,
  Apple,
  Cpu,
  Sparkles,
  ShieldCheck,
  TerminalSquare,
  KeyRound,
  ArrowRight,
  CheckCircle2,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";

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
    <div className="relative min-h-screen overflow-x-clip bg-background text-foreground">
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 -z-0 bg-[radial-gradient(circle_at_10%_10%,rgba(245,158,11,0.12),transparent_35%),radial-gradient(circle_at_90%_20%,rgba(59,130,246,0.10),transparent_30%),radial-gradient(circle_at_60%_90%,rgba(16,185,129,0.08),transparent_35%)]"
      />
      <Navbar />
      <main className="relative z-10">
        <Hero latestRelease={latestRelease} />
        <DemoSection />
        <WorkflowSection />
        <DownloadSection releases={releases} />
      </main>
      <footer className="border-t border-border/70 py-8 px-6">
        <div className="max-w-6xl mx-auto flex flex-col sm:flex-row gap-3 sm:items-center sm:justify-between text-sm text-muted-foreground">
          <p>Humlex is open source and built for macOS 14+.</p>
          <a
            href="https://github.com/lassejlv/humlex"
            target="_blank"
            rel="noreferrer"
            className="hover:text-foreground transition-colors"
          >
            View on GitHub
          </a>
        </div>
      </footer>
    </div>
  );
}

function Navbar() {
  return (
    <nav className="fixed top-0 left-0 right-0 z-50 border-b border-border/70 bg-background/70 backdrop-blur-xl">
      <div className="max-w-6xl mx-auto px-6 h-16 flex items-center justify-between">
        <Link to="/" className="flex items-center gap-2">
          <img src="/icon.png" alt="Humlex" className="w-6 h-6 rounded-lg" />
          <span className="text-lg font-semibold tracking-tight">Humlex</span>
        </Link>

        <div className="hidden md:flex items-center gap-8 text-sm">
          <a
            href="#features"
            className="text-muted-foreground hover:text-foreground transition-colors"
          >
            Features
          </a>
          <a
            href="#workflow"
            className="text-muted-foreground hover:text-foreground transition-colors"
          >
            Workflow
          </a>
          <a
            href="#download"
            className="text-muted-foreground hover:text-foreground transition-colors"
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
    <section className="pt-28 pb-14 px-6">
      <div className="max-w-6xl mx-auto grid lg:grid-cols-[1.1fr_0.9fr] gap-12 items-center">
        <div>
          <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full border border-border bg-card/70 text-xs font-medium text-muted-foreground mb-5">
            <Sparkles className="w-3.5 h-3.5 text-primary" />
            Native chat workspace for engineers on macOS
          </div>

          <h1 className="text-4xl md:text-6xl font-semibold tracking-tight leading-[1.05] mb-5">
            AI chat that feels at home on your Mac
          </h1>
          <p className="text-lg text-muted-foreground max-w-xl leading-relaxed mb-8">
            Humlex unifies providers, agent workflows, and model switching in a
            fast native client. Keep focus, move faster, and keep credentials in
            Keychain.
          </p>

          <div className="flex flex-col sm:flex-row items-start sm:items-center gap-3 mb-7">
            <Button size="lg" className="gap-2 px-6" asChild>
              <a href="#download">
                <Apple className="w-4 h-4" />
                Download for macOS
              </a>
            </Button>
            <Button variant="outline" size="lg" className="gap-2 px-6" asChild>
              <a href="#features">
                Explore features
                <ArrowRight className="w-4 h-4" />
              </a>
            </Button>
          </div>

          {latestRelease && (
            <p className="text-sm text-muted-foreground">
              Latest release:{" "}
              <span className="text-foreground font-medium">
                {latestRelease.version}
              </span>{" "}
              · macOS 14+ supported
            </p>
          )}
        </div>

        <div className="rounded-2xl border border-border bg-card/70 p-3 shadow-[0_20px_50px_rgba(0,0,0,0.25)]">
          <img
            src="/example1.png"
            alt="Humlex app preview"
            className="w-full rounded-xl border border-border/70"
          />
          <div className="grid grid-cols-2 gap-2 mt-3">
            <StatChip title="Providers" value="10+" />
            <StatChip title="Modes" value="Chat + Agent" />
            <StatChip title="Platform" value="macOS 14+" />
            <StatChip title="Security" value="Keychain" />
          </div>
        </div>
      </div>
    </section>
  );
}

function StatChip({ title, value }: { title: string; value: string }) {
  return (
    <div className="rounded-lg border border-border/70 bg-background/60 px-3 py-2">
      <p className="text-[11px] uppercase tracking-wide text-muted-foreground">
        {title}
      </p>
      <p className="text-sm font-medium mt-0.5">{value}</p>
    </div>
  );
}

function DemoSection() {
  const cards = [
    {
      icon: Sparkles,
      title: "Multiple providers",
      description:
        "Connect OpenAI, Anthropic, OpenRouter, Gemini, Vercel AI and local models in one UI.",
    },
    {
      icon: TerminalSquare,
      title: "Agent mode",
      description:
        "Switch to agent mode to run commands, edit files, and work with MCP tools in-context.",
    },
    {
      icon: ShieldCheck,
      title: "Secure by default",
      description:
        "API keys are stored in macOS Keychain and stay local to your machine.",
    },
    {
      icon: KeyRound,
      title: "Fast setup",
      description:
        "Import chats, switch themes, configure providers, and start shipping in minutes.",
    },
  ];

  return (
    <section id="features" className="py-16 px-6">
      <div className="max-w-6xl mx-auto">
        <div className="mb-8 max-w-2xl">
          <h2 className="text-3xl font-semibold tracking-tight mb-3">
            Built for daily AI workflows
          </h2>
          <p className="text-muted-foreground leading-relaxed">
            A focused interface for chats, code generation, and local agent
            execution without leaving macOS conventions.
          </p>
        </div>

        <div className="rounded-2xl overflow-hidden bg-card/70 border border-border shadow-sm">
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

        <div className="mt-12 grid md:grid-cols-2 gap-4">
          {cards.map((card) => (
            <FeatureCard
              key={card.title}
              icon={card.icon}
              title={card.title}
              description={card.description}
            />
          ))}
        </div>
      </div>
    </section>
  );
}

function FeatureCard({
  icon: Icon,
  title,
  description,
}: {
  icon: React.ComponentType<{ className?: string }>;
  title: string;
  description: string;
}) {
  return (
    <div className="rounded-xl border border-border bg-card/65 p-5">
      <div className="inline-flex items-center justify-center h-9 w-9 rounded-lg bg-primary/15 text-primary mb-3">
        <Icon className="w-4 h-4" />
      </div>
      <h3 className="text-base font-semibold mb-1.5">{title}</h3>
      <p className="text-sm text-muted-foreground leading-relaxed">{description}</p>
    </div>
  );
}

function WorkflowSection() {
  const steps = [
    {
      title: "Choose provider + model",
      detail: "Select the model per task and keep all APIs in one place.",
    },
    {
      title: "Chat, attach, iterate",
      detail: "Use files, markdown rendering, and context indicators while iterating.",
    },
    {
      title: "Switch to agent mode",
      detail: "Run tools and commands in your working directory without leaving the thread.",
    },
  ];

  return (
    <section id="workflow" className="py-12 px-6">
      <div className="max-w-6xl mx-auto rounded-2xl border border-border bg-card/50 p-6 md:p-8">
        <h2 className="text-2xl md:text-3xl font-semibold tracking-tight mb-2">
          One workflow from prompt to execution
        </h2>
        <p className="text-muted-foreground mb-8 max-w-3xl">
          Keep your ideation and execution in the same timeline instead of
          jumping between disconnected tools.
        </p>

        <div className="grid md:grid-cols-3 gap-4">
          {steps.map((step, idx) => (
            <div key={step.title} className="rounded-xl border border-border bg-background/50 p-4">
              <p className="text-xs font-semibold text-primary mb-2">
                Step {idx + 1}
              </p>
              <h3 className="font-medium mb-2">{step.title}</h3>
              <p className="text-sm text-muted-foreground leading-relaxed">
                {step.detail}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

function DownloadSection({ releases }: { releases: Release[] }) {
  const latestRelease = releases[0];
  const [arch, setArch] = useState<"auto" | "intel" | "apple">("auto");

  useEffect(() => {
    if (typeof navigator === "undefined") return;
    const ua = navigator.userAgent.toLowerCase();
    if (ua.includes("intel")) setArch("intel");
    if (ua.includes("apple") || ua.includes("arm") || ua.includes("silicon")) {
      setArch("apple");
    }
  }, []);

  const releaseSummary = useMemo(() => {
    if (!latestRelease?.notes) return null;
    const lines = latestRelease.notes
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => line.length > 0)
      .map((line) => line.replace(/^[-*#\s`>]+/, ""))
      .filter((line) => line.length > 0);
    return lines[0] ?? null;
  }, [latestRelease?.notes]);

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
    <section id="download" className="py-20 px-6">
      <div className="max-w-3xl mx-auto text-center">
        <h2 className="text-3xl font-semibold mb-3 tracking-tight">
          Download Humlex
        </h2>
        <p className="text-muted-foreground mb-8 leading-relaxed">
          Free and open source. Pick your architecture and install with one
          click.
        </p>

        {latestRelease ? (
          <div className="p-6 rounded-2xl bg-card/70 border border-border shadow-sm">
            <p className="text-sm text-muted-foreground mb-1">Latest Release</p>
            <p className="text-2xl font-semibold mb-1">
              {latestRelease.version}
            </p>
            <p className="text-sm text-muted-foreground mb-5">
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
                  <span className="inline-flex items-center gap-1.5">
                    <Sparkles className="w-3.5 h-3.5" />
                    Auto
                  </span>
                </button>
                <button
                  onClick={() => setArch("intel")}
                  className={`px-4 py-1.5 text-sm font-medium rounded-full transition-all ${
                    arch === "intel"
                      ? "bg-background text-foreground shadow-sm"
                      : "text-muted-foreground hover:text-foreground"
                  }`}
                >
                  <span className="inline-flex items-center gap-1.5">
                    <Cpu className="w-3.5 h-3.5" />
                    Intel
                  </span>
                </button>
                <button
                  onClick={() => setArch("apple")}
                  className={`px-4 py-1.5 text-sm font-medium rounded-full transition-all ${
                    arch === "apple"
                      ? "bg-background text-foreground shadow-sm"
                      : "text-muted-foreground hover:text-foreground"
                  }`}
                >
                  <span className="inline-flex items-center gap-1.5">
                    <Apple className="w-3.5 h-3.5" />
                    Apple Silicon
                  </span>
                </button>
              </div>
            )}

            {downloadInfo ? (
              <>
                <Button className="gap-2 px-6" asChild>
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
              <Button className="gap-2 px-6" disabled>
                <Download className="w-4 h-4" />
                No DMG Available
              </Button>
            )}

            <div className="mt-5 rounded-lg border border-border/70 bg-background/50 p-3 text-left">
              <p className="text-xs text-muted-foreground mb-1 uppercase tracking-wide">
                Release highlight
              </p>
              <p className="text-sm">
                {releaseSummary ?? "Stability and performance improvements."}
              </p>
            </div>

            <div className="mt-4 flex justify-center">
              <p className="inline-flex items-center gap-1.5 text-xs text-muted-foreground">
                <CheckCircle2 className="w-3.5 h-3.5 text-emerald-500" />
                Signed build · macOS 14+ required
              </p>
            </div>
          </div>
        ) : (
          <div className="p-6 rounded-xl bg-card border border-border">
            <p className="text-muted-foreground">No releases available.</p>
          </div>
        )}

        {releases.length > 1 && (
          <div className="mt-10 text-left">
            <p className="text-sm text-muted-foreground mb-4 text-center">
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
                    <span className="text-sm font-medium">{release.version}</span>
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
