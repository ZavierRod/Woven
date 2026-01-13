import SwiftUI
import UIKit

/// A zoomable image view with pinch-to-zoom and pan gestures, behaving like iOS Photos app
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    
    func makeUIView(context: Context) -> CenteringScrollView {
        let scrollView = CenteringScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        
        scrollView.addSubview(imageView)
        scrollView.imageView = imageView
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView
        
        // Add double tap gesture
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        
        return scrollView
    }
    
    func updateUIView(_ scrollView: CenteringScrollView, context: Context) {
        guard let imageView = context.coordinator.imageView else { return }
        
        // Update image if changed
        if imageView.image !== image {
            imageView.image = image
            context.coordinator.needsZoomSetup = true
        }
        
        // Trigger layout update
        scrollView.setNeedsLayout()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        weak var scrollView: CenteringScrollView?
        var needsZoomSetup = true
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return imageView
        }
        
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImageInScrollView(scrollView)
        }
        
        func centerImageInScrollView(_ scrollView: UIScrollView) {
            guard let imageView = imageView else { return }
            
            let boundsSize = scrollView.bounds.size
            var frameToCenter = imageView.frame
            
            // Center horizontally
            if frameToCenter.size.width < boundsSize.width {
                frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
            } else {
                frameToCenter.origin.x = 0
            }
            
            // Center vertically
            if frameToCenter.size.height < boundsSize.height {
                frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2
            } else {
                frameToCenter.origin.y = 0
            }
            
            imageView.frame = frameToCenter
        }
        
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView,
                  let imageView = imageView else { return }
            
            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                // Zoom out to fit
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                // Zoom in to 2x (or max) at the tap point
                let zoomScale = min(scrollView.minimumZoomScale * 2.5, scrollView.maximumZoomScale)
                let tapPoint = gesture.location(in: imageView)
                
                let zoomRect = CGRect(
                    x: tapPoint.x - scrollView.bounds.width / (2 * zoomScale),
                    y: tapPoint.y - scrollView.bounds.height / (2 * zoomScale),
                    width: scrollView.bounds.width / zoomScale,
                    height: scrollView.bounds.height / zoomScale
                )
                
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }
    }
}

/// Custom scroll view that handles centering and proper zoom setup after layout
class CenteringScrollView: UIScrollView {
    var imageView: UIImageView?
    private var hasSetupInitialZoom = false
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        guard let imageView = imageView,
              let image = imageView.image,
              bounds.width > 0, bounds.height > 0,
              image.size.width > 0, image.size.height > 0 else {
            return
        }
        
        // Setup zoom on first layout with valid bounds
        if !hasSetupInitialZoom {
            hasSetupInitialZoom = true
            setupZoomScale(for: image)
        }
        
        centerImage()
    }
    
    private func setupZoomScale(for image: UIImage) {
        let imageSize = image.size
        let boundsSize = bounds.size
        
        // Calculate minimum scale to fit image completely (aspect fit)
        let widthScale = boundsSize.width / imageSize.width
        let heightScale = boundsSize.height / imageSize.height
        let minScale = min(widthScale, heightScale)
        
        // Set zoom scales
        minimumZoomScale = minScale
        maximumZoomScale = max(minScale * 4.0, 4.0)
        
        // Set imageView frame to actual image size
        imageView?.frame = CGRect(origin: .zero, size: imageSize)
        
        // Set content size to image size
        contentSize = imageSize
        
        // Set initial zoom to fit the screen (not zoomed in)
        zoomScale = minScale
    }
    
    private func centerImage() {
        guard let imageView = imageView else { return }
        
        let boundsSize = bounds.size
        var frameToCenter = imageView.frame
        
        // Center horizontally
        if frameToCenter.size.width < boundsSize.width {
            frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
        } else {
            frameToCenter.origin.x = 0
        }
        
        // Center vertically
        if frameToCenter.size.height < boundsSize.height {
            frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2
        } else {
            frameToCenter.origin.y = 0
        }
        
        imageView.frame = frameToCenter
    }
    
    func resetZoom() {
        hasSetupInitialZoom = false
        setNeedsLayout()
    }
}
