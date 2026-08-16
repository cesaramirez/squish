class Squish < Formula
  desc "Tiny, fast image optimizer for the terminal with optional vision-AI naming"
  homepage "https://github.com/heycesar/squish"
  url "https://github.com/heycesar/squish/archive/refs/tags/v0.6.0.tar.gz"
  # Compute the real checksum with:
  #   curl -sL https://github.com/heycesar/squish/archive/refs/tags/v0.6.0.tar.gz | shasum -a 256
  sha256 "3dc71d4d8861199498345189c7c74d465c4c2f1b514d68c6a55e4ea3e4279bdc"
  license "MIT"
  version "0.6.0"

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
    zsh_completion.install  "completions/squish.zsh"  => "_squish"
    bash_completion.install "completions/squish.bash" => "squish"
  end

  test do
    assert_match(/squish|Usage/i, shell_output("#{bin}/squish --help"))
  end
end
