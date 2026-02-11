import { createServerFn } from '@tanstack/react-start'

interface GitHubAsset {
  name: string
  browser_download_url: string
  size: number
}

interface GitHubRelease {
  tag_name: string
  name: string
  published_at: string
  body: string
  assets: GitHubAsset[]
}

export interface ReleaseAsset {
  url: string
  size: string
}

export interface Release {
  version: string
  name: string
  publishedAt: string
  intel?: ReleaseAsset
  appleSilicon?: ReleaseAsset
  universal?: ReleaseAsset
  notes: string
}

function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i]
}

function findAsset(assets: GitHubAsset[], patterns: string[]): GitHubAsset | undefined {
  return assets.find((asset) =>
    patterns.some((pattern) =>
      asset.name.toLowerCase().includes(pattern.toLowerCase())
    )
  )
}

export const fetchReleases = createServerFn({ method: 'GET' }).handler(
  async (): Promise<Release[]> => {
    try {
      const response = await fetch(
        'https://api.github.com/repos/lassejlv/humlex/releases',
        {
          headers: {
            Accept: 'application/vnd.github.v3+json',
          },
        }
      )

      if (!response.ok) {
        throw new Error(`GitHub API error: ${response.status}`)
      }

      const releases: GitHubRelease[] = await response.json()

      return releases.map((release) => {
        const assets = release.assets.filter((asset) =>
          asset.name.endsWith('.dmg')
        )

        const intelAsset =
          findAsset(assets, ['intel', 'x86_64', 'amd64']) ||
          assets.find((a) => a.name.includes('x86'))

        const appleSiliconAsset =
          findAsset(assets, ['arm64', 'apple', 'silicon', 'm1', 'm2', 'm3']) ||
          assets.find((a) => a.name.includes('arm'))

        const universalAsset = findAsset(assets, ['universal'])

        const fallbackAsset = assets[0]

        return {
          version: release.tag_name,
          name: release.name,
          publishedAt: new Date(release.published_at).toLocaleDateString(
            'en-US',
            {
              year: 'numeric',
              month: 'long',
              day: 'numeric',
            }
          ),
          intel: intelAsset
            ? { url: intelAsset.browser_download_url, size: formatBytes(intelAsset.size) }
            : undefined,
          appleSilicon: appleSiliconAsset
            ? { url: appleSiliconAsset.browser_download_url, size: formatBytes(appleSiliconAsset.size) }
            : undefined,
          universal: universalAsset
            ? { url: universalAsset.browser_download_url, size: formatBytes(universalAsset.size) }
            : fallbackAsset && !intelAsset && !appleSiliconAsset
            ? { url: fallbackAsset.browser_download_url, size: formatBytes(fallbackAsset.size) }
            : undefined,
          notes: release.body,
        }
      })
    } catch {
      return []
    }
  }
)
