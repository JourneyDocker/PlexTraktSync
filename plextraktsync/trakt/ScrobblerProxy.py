from __future__ import annotations

from functools import cached_property
from typing import TYPE_CHECKING

from plextraktsync.factory import factory, logging

if TYPE_CHECKING:
    from trakt.sync import Scrobbler


class ScrobblerProxy:
    """
    Proxy to Scrobbler that queues requests to update trakt
    """

    logger = logging.getLogger(__name__)

    def __init__(self, scrobbler: Scrobbler, threshold=80):
        self.scrobbler = scrobbler
        self.threshold = threshold

    def update(self, progress: float):
        self.logger.debug(f"update({self.scrobbler.media}): {progress}")
        self.queue.scrobble_update((self.scrobbler, progress))

    def pause(self, progress: float):
        if progress >= 80:
            # Trakt will reject pause requests at 80% or above
            self.logger.debug(f"skip pause({self.scrobbler.media}): {progress} (>= 80%)")
            return

        # Trakt requires pause to be at least 1%
        progress = max(1.0, progress)
        self.logger.debug(f"pause({self.scrobbler.media}): {progress}")
        self.queue.scrobble_pause((self.scrobbler, progress))

    def stop(self, progress: float):
        if progress >= self.threshold:
            self.logger.debug(f"stop({self.scrobbler.media}): {progress}")
            self.queue.scrobble_stop((self.scrobbler, progress))
            return

        if progress >= 80:
            # Don't send pause when progress is >= 80% but below user threshold
            self.logger.debug(f"skip pause({self.scrobbler.media}): {progress} (between 80% and threshold)")
            return

        # Treat as pause for anything below 80%
        progress = max(1.0, progress)
        self.logger.debug(f"pause({self.scrobbler.media}): {progress}")
        self.queue.scrobble_pause((self.scrobbler, progress))

    @cached_property
    def queue(self):
        return factory.queue
