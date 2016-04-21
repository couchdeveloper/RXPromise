//
//  DLog.h
//
//  Copyright 2013 Andreas Grosam
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.


#ifndef DLOG_H
#define DLOG_H

#define DEBUG_LOGLEVEL_DEBUG    4
#define DEBUG_LOGLEVEL_INFO     3
#define DEBUG_LOGLEVEL_WARN     2
#define DEBUG_LOGLEVEL_ERROR    1
#define DEBUG_LOGLEVEL_NONE     0


// DEBUG_LOG_MIN
// If DEBUG_LOG and DEBUG_LOG_MIN is defined and DEBUG_LOG_MIN > DEBUG_LOG,
// DEBUG_LOG will be set to DEBUG_LOG_MIN.
// For example, if DEBUG_LOG_MIN is defined as DEBUG_LOGLEVEL_WARN and DEBUG_LOG
// is defined as DEBUGG_LOG_ERROR, all warnings and errors will be logged.
//
// DEBUG_LOG_MAX
// If DEBUG_LOG and DEBUG_LOG_MAX is defined and DEBUG_LOG > DEBUG_LOG_MAX
// DEBUG_LOG will be set to DEBUG_LOG_MAX.
// For example, if DEBUG_LOG is defined as DEBUG_LOGLEVEL_DEBUG and DEBUG_LOG_MAX
// is defined as DEBUG_LOGLEVEL_ERROR, DEBUG_LOG will become DEBUG_LOGLEVEL_ERROR,
// which only logs all errors (and messages with higher severity).


#if !defined (DEBUG_LOG)
    #if defined (NDEBUG)
        #define DEBUG_LOG DEBUG_LOGLEVEL_ERROR
    #elif defined (DEBUG)
        #define DEBUG_LOG DEBUG_LOGLEVEL_DEBUG
        #warning DEBUG_LOG not defined - set to default: DEBUG_LOGLEVEL_DEBUG
    #else
        #define DEBUG_LOG DEBUG_LOGLEVEL_WARN
        #warning DEBUG_LOG not defined - set to default: DEBUG_LOGLEVEL_WARN
    #endif
#else
    #if defined (DEBUG_LOG_MIN) && (DEBUG_LOG_MIN > DEBUG_LOG)
        #undef DEBUG_LOG
        #define DEBUG_LOG DEBUG_LOG_MIN
    #endif
    #if defined (DEBUG_LOG_MAX) && (DEBUG_LOG_MAX < DEBUG_LOG)
        #undef DEBUG_LOG
        #define DEBUG_LOG DEBUG_LOG_MAX
    #endif
#endif

#if defined (DEBUG_LOG) && (DEBUG_LOG >= DEBUG_LOGLEVEL_DEBUG)
#define DLogDebug(...) NSLog(@"%s %@", __PRETTY_FUNCTION__, [NSString stringWithFormat:__VA_ARGS__])
#else
#define DLogDebug(...) do { } while (0)
#endif

#if defined (DEBUG_LOG) && (DEBUG_LOG >= DEBUG_LOGLEVEL_INFO)
#define DLogInfo(...) NSLog(@"INFO: %s %@", __PRETTY_FUNCTION__, [NSString stringWithFormat:__VA_ARGS__])
#else
#define DLogInfo(...) do { } while (0)
#endif

#if defined (DEBUG_LOG) && (DEBUG_LOG >= DEBUG_LOGLEVEL_WARN)
#define DLogWarn(...) NSLog(@"WARNING: %s %@", __PRETTY_FUNCTION__, [NSString stringWithFormat:__VA_ARGS__])
#else
#define DLogWarn(...) do { } while (0)
#endif

#if !defined (DEBUG_LOG) || (DEBUG_LOG >= DEBUG_LOGLEVEL_ERROR)
#define DLogError(...) NSLog(@"ERROR: %s %@", __PRETTY_FUNCTION__, [NSString stringWithFormat:__VA_ARGS__])
#else
#define DLogError(...) do { } while (0)
#endif

#define DLog(...) NSLog(@"%s %@", __PRETTY_FUNCTION__, [NSString stringWithFormat:__VA_ARGS__])


#endif
