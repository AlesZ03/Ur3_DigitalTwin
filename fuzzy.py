import cv2
import numpy as np

def fuzzy_edge_detection(img):
    # Szürkeárnyalat
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    # Zajcsökkentés
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)

    # Sobel deriváltak (él-információk)
    sobelx = cv2.Sobel(blurred, cv2.CV_64F, 1, 0, ksize=3)
    sobely = cv2.Sobel(blurred, cv2.CV_64F, 0, 1, ksize=3)
    gradient_magnitude = np.sqrt(sobelx**2 + sobely**2)

    # Normalizálás [0..1] közé
    gradient_magnitude = cv2.normalize(gradient_magnitude, None, 0, 1, cv2.NORM_MINMAX)

    # Fuzzy tagsági függvények (alacsony, közepes, magas él-erősség)
    low = np.exp(-((gradient_magnitude - 0.2) ** 2) / (2 * 0.1 ** 2))
    medium = np.exp(-((gradient_magnitude - 0.5) ** 2) / (2 * 0.1 ** 2))
    high = np.exp(-((gradient_magnitude - 0.8) ** 2) / (2 * 0.1 ** 2))

    # Fuzzy szabály: erős él = közepes ∨ magas tagság
    fuzzy_edges = np.maximum(medium, high)

    # Binarizálás
    edges = (fuzzy_edges > 0.5).astype(np.uint8) * 255
    return edges

if __name__ == "__main__":
    img = cv2.imread("kep.jpg")  # kép betöltése
    edges = fuzzy_edge_detection(img)

    cv2.imshow("Eredeti", img)
    cv2.imshow("Fuzzy Edge Detection", edges)
    cv2.waitKey(0)
    cv2.destroyAllWindows()
