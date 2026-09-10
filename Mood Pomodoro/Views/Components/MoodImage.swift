//
//  MoodImage.swift
//  Mood Pomodoro
//

import SwiftUI

/// The mushroom-character illustration for a mood, sized consistently
/// wherever it appears (in-app UI only — notification actions can't render
/// custom images, so those still use `mood.emoji`).
struct MoodImage: View {
    let mood: Mood
    var size: CGFloat = 48

    var body: some View {
        Image(mood.imageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}
