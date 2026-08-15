class Squish < Formula
  desc "Tiny, fast image optimizer for the terminal with optional vision-AI naming"
  homepage "https://github.com/cesaramirez/squish"
  url "https://github.com/cesaramirez/squish/archive/refs/tags/v0.5.0.tar.gz"
  # Compute the real checksum with:
  #   curl -sL https://github.com/cesaramirez/squish/archive/refs/tags/v0.5.0.tar.gz | shasum -a 256
  sha256 "01f9072d73bbb4995320ff5356873e9ba37fb28c8f3a798de4d0e8a28f18fa4c"
  license "MIT"
  version "0.5.0"

  # Required optimizers.
  depends_on "pngquant"
  depends_on "oxipng"

  # Optional runtime tools. Kept out of the required set so the formula stays
  # lightweight; imagemagick unlocks resize/convert, webp adds WebP output, and
  # jq is used by the vision-AI naming feature.
  depends_on "imagemagick" => :recommended
  depends_on "webp" => :optional
  depends_on "jq" => :optional

  def install
    bin.install "squish.sh" => "squish"
  end

  test do
    assert_match(/squish|Usage/i, shell_output("#{bin}/squish --help"))
  end
end
