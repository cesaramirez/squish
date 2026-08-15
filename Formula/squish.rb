class Squish < Formula
  desc "Tiny, fast image optimizer for the terminal with optional vision-AI naming"
  homepage "https://github.com/cesaramirez/squish"
  url "https://github.com/cesaramirez/squish/archive/refs/tags/v0.3.0.tar.gz"
  # Compute the real checksum with:
  #   curl -sL https://github.com/cesaramirez/squish/archive/refs/tags/v0.3.0.tar.gz | shasum -a 256
  sha256 "260b201ff61f000008de8c217f2cf046e3c3db75b5153e83d7d44c795829fa65"
  license "MIT"
  version "0.3.0"

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
