//
//  Constants.m
//  OpenArchive
//
//  Created by Benjamin Erhart on 01.08.18.
//  Copyright © 2018 Open Archive. All rights reserved.
//

#import "Constants.h"

#define MACRO_STRING_(m) #m
#define MACRO_STRING(m) @MACRO_STRING_(m)

@implementation Constants

+ (NSString *) appGroup {
    return MACRO_STRING(OA_APP_GROUP);
}

+ (NSString *) teamId {
    return MACRO_STRING(DEVELOPMENT_TEAM);
}

+ (NSString *) dropboxKey {
    return MACRO_STRING(DROPBOX_KEY);
}

@end
