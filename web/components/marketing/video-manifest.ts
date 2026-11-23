// Written by scripts/web-scene-video.py. Don't edit by hand.
// Per slot: the wide and phone loops in Light and Dark (H.264, plus AV1 where it is smaller) and the
// foreground cut-out's box in fractions of the picture.
export const sceneVideos = {
  "scene-features": {
    "mobile": {
      "dark": {
        "h": 648,
        "h264": "/marketing/video/scene-features-mobile-dark.mp4",
        "w": 720
      },
      "light": {
        "h": 648,
        "h264": "/marketing/video/scene-features-mobile-light.mp4",
        "w": 720
      }
    },
    "wide": {
      "dark": {
        "av1": "/marketing/video/scene-features-wide-dark.av1.mp4",
        "h": 1080,
        "h264": "/marketing/video/scene-features-wide-dark.mp4",
        "w": 1920
      },
      "light": {
        "av1": "/marketing/video/scene-features-wide-light.av1.mp4",
        "h": 1080,
        "h264": "/marketing/video/scene-features-wide-light.mp4",
        "w": 1920
      }
    }
  },
  "scene-footer": {
    "mobile": {
      "dark": {
        "h": 498,
        "h264": "/marketing/video/scene-footer-mobile-dark.mp4",
        "w": 720
      },
      "light": {
        "h": 498,
        "h264": "/marketing/video/scene-footer-mobile-light.mp4",
        "w": 720
      }
    },
    "wide": {
      "dark": {
        "av1": "/marketing/video/scene-footer-wide-dark.av1.mp4",
        "h": 824,
        "h264": "/marketing/video/scene-footer-wide-dark.mp4",
        "w": 1920
      },
      "light": {
        "av1": "/marketing/video/scene-footer-wide-light.av1.mp4",
        "h": 824,
        "h264": "/marketing/video/scene-footer-wide-light.mp4",
        "w": 1920
      }
    }
  },
  "scene-hero": {
    "fg": {
      "mobile": [
        0.0,
        0.845,
        1.0,
        1.0
      ],
      "wide": [
        0.2,
        0.845,
        0.76,
        1.0
      ]
    },
    "mobile": {
      "dark": {
        "h": 960,
        "h264": "/marketing/video/scene-hero-mobile-dark.mp4",
        "w": 720
      },
      "light": {
        "h": 960,
        "h264": "/marketing/video/scene-hero-mobile-light.mp4",
        "w": 720
      }
    },
    "wide": {
      "dark": {
        "av1": "/marketing/video/scene-hero-wide-dark.av1.mp4",
        "h": 1280,
        "h264": "/marketing/video/scene-hero-wide-dark.mp4",
        "w": 1920
      },
      "light": {
        "av1": "/marketing/video/scene-hero-wide-light.av1.mp4",
        "h": 1280,
        "h264": "/marketing/video/scene-hero-wide-light.mp4",
        "w": 1920
      }
    }
  },
  "scene-page": {
    "mobile": {
      "dark": {
        "h": 412,
        "h264": "/marketing/video/scene-page-mobile-dark.mp4",
        "w": 960
      },
      "light": {
        "h": 412,
        "h264": "/marketing/video/scene-page-mobile-light.mp4",
        "w": 960
      }
    },
    "wide": {
      "dark": {
        "av1": "/marketing/video/scene-page-wide-dark.av1.mp4",
        "h": 824,
        "h264": "/marketing/video/scene-page-wide-dark.mp4",
        "w": 1920
      },
      "light": {
        "av1": "/marketing/video/scene-page-wide-light.av1.mp4",
        "h": 824,
        "h264": "/marketing/video/scene-page-wide-light.mp4",
        "w": 1920
      }
    }
  },
  "scene-pricing": {
    "mobile": {
      "dark": {
        "h": 810,
        "h264": "/marketing/video/scene-pricing-mobile-dark.mp4",
        "w": 720
      },
      "light": {
        "h": 810,
        "h264": "/marketing/video/scene-pricing-mobile-light.mp4",
        "w": 720
      }
    },
    "wide": {
      "dark": {
        "av1": "/marketing/video/scene-pricing-wide-dark.av1.mp4",
        "h": 1080,
        "h264": "/marketing/video/scene-pricing-wide-dark.mp4",
        "w": 1920
      },
      "light": {
        "av1": "/marketing/video/scene-pricing-wide-light.av1.mp4",
        "h": 1080,
        "h264": "/marketing/video/scene-pricing-wide-light.mp4",
        "w": 1920
      }
    }
  },
  "spot-private": {
    "wide": {
      "dark": {
        "h": 498,
        "h264": "/marketing/video/spot-private-dark.mp4",
        "w": 480
      },
      "light": {
        "h": 498,
        "h264": "/marketing/video/spot-private-light.mp4",
        "w": 480
      }
    }
  },
  "spot-pro": {
    "wide": {
      "dark": {
        "h": 674,
        "h264": "/marketing/video/spot-pro-dark.mp4",
        "w": 480
      },
      "light": {
        "h": 674,
        "h264": "/marketing/video/spot-pro-light.mp4",
        "w": 480
      }
    }
  },
  "spot-record": {
    "wide": {
      "dark": {
        "h": 404,
        "h264": "/marketing/video/spot-record-dark.mp4",
        "w": 480
      },
      "light": {
        "h": 404,
        "h264": "/marketing/video/spot-record-light.mp4",
        "w": 480
      }
    }
  },
  "spot-share": {
    "wide": {
      "dark": {
        "h": 384,
        "h264": "/marketing/video/spot-share-dark.mp4",
        "w": 480
      },
      "light": {
        "h": 384,
        "h264": "/marketing/video/spot-share-light.mp4",
        "w": 480
      }
    }
  },
  "spot-watch": {
    "wide": {
      "dark": {
        "h": 504,
        "h264": "/marketing/video/spot-watch-dark.mp4",
        "w": 480
      },
      "light": {
        "h": 504,
        "h264": "/marketing/video/spot-watch-light.mp4",
        "w": 480
      }
    }
  }
} as const;
